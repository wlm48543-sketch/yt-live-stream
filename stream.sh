#!/bin/bash

echo "Rclone কনফিগারেশন এবং ফোল্ডার সেটআপ..."
mkdir -p ~/.config/rclone
echo "$RCLONE_CONFIG_DATA" > ~/.config/rclone/rclone.conf
mkdir -p ./videos

# --- ১. টাইটেল সিলেকশন এবং লুপ লজিক ---
if [ ! -f Tittles.txt ]; then
    echo "❌ Tittles.txt ফাইল পাওয়া যায়নি! ডিফল্ট টাইটেল ব্যবহার করা হবে।"
    CURRENT_TITLE="My 24/7 Live Stream"
else
    # history.json থেকে লাস্ট ইনডেক্স পড়া (না থাকলে ০)
    LAST_INDEX=$(jq -r '.last_index // 0' history.json 2>/dev/null || echo "0")
    TOTAL_TITLES=$(wc -l < Tittles.txt)
    
    NEXT_INDEX=$((LAST_INDEX + 1))
    if [ "$NEXT_INDEX" -gt "$TOTAL_TITLES" ]; then
        NEXT_INDEX=1
    fi
    
    # নির্দিষ্ট লাইনের টাইটেলটি বের করা
    CURRENT_TITLE=$(sed "${NEXT_INDEX}q;d" Tittles.txt)
    echo "✅ নির্বাচিত টাইটেল: $CURRENT_TITLE"
    
    # history.json আপডেট এবং গিটহাবে সেভ করা
    echo "{\"last_index\": $NEXT_INDEX}" > history.json
    git config --global user.name "github-actions[bot]"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"
    git add history.json
    git commit -m "Auto-update title index to $NEXT_INDEX"
    git push || echo "⚠️ গিটহাবে পুশ করতে সমস্যা হয়েছে, তবে লাইভ চলবে।"
fi

# --- ২. YouTube API দিয়ে টাইটেল পরিবর্তন ---
echo "YouTube API-এর মাধ্যমে টাইটেল আপডেট করা হচ্ছে..."

ACCESS_TOKEN=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "refresh_token=$REFRESH_TOKEN" \
  -d "grant_type=refresh_token" | jq -r .access_token)

if [ "$ACCESS_TOKEN" != "null" ] && [ -n "$ACCESS_TOKEN" ]; then
    # Persistent (ডিফল্ট) ব্রডকাস্ট আইডি বের করা
    BROADCAST_RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
      "https://www.googleapis.com/youtube/v3/liveBroadcasts?part=id,snippet&broadcastType=persistent&mine=true")
      
    BROADCAST_ID=$(echo "$BROADCAST_RESPONSE" | jq -r '.items[0].id')
    
    if [ "$BROADCAST_ID" != "null" ] && [ -n "$BROADCAST_ID" ]; then
        SNIPPET=$(echo "$BROADCAST_RESPONSE" | jq '.items[0].snippet')
        UPDATED_SNIPPET=$(echo "$SNIPPET" | jq --arg title "$CURRENT_TITLE" '.title = $title')
        PAYLOAD=$(jq -n --arg id "$BROADCAST_ID" --argjson snippet "$UPDATED_SNIPPET" '{id: $id, snippet: $snippet}')
        
        # টাইটেল আপডেট রিকোয়েস্ট পাঠানো
        UPDATE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "https://www.googleapis.com/youtube/v3/liveBroadcasts?part=snippet" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json" \
          -d "$PAYLOAD")
          
        if [ "$UPDATE_STATUS" -eq 200 ]; then
            echo "🎉 ইউটিউবে টাইটেল সফলভাবে আপডেট হয়েছে!"
        else
            echo "⚠️ টাইটেল আপডেট ফেইল করেছে (HTTP: $UPDATE_STATUS)।"
        fi
    else
        echo "⚠️ Persistent Broadcast খুঁজে পাওয়া যায়নি।"
    fi
else
    echo "⚠️ Access Token জেনারেট করা যায়নি। ক্রেডেনশিয়ালস চেক করুন।"
fi

# --- ৩. স্ট্রিমিং এবং র‍্যান্ডম টাইমার লজিক ---
RANDOM_DURATION=$(( (RANDOM % 7201) + 10800 ))
HOURS=$(( RANDOM_DURATION / 3600 ))
MINUTES=$(( (RANDOM_DURATION % 3600) / 60 ))
echo "✅ এই লাইভ স্ট্রিমটি চলবে: $HOURS ঘণ্টা $MINUTES মিনিট ($RANDOM_DURATION সেকেন্ড)"

END_TIME=$(( $(date +%s) + RANDOM_DURATION ))

echo "গুগল ড্রাইভ থেকে ভিডিও সিঙ্ক করা হচ্ছে..."
rclone sync gdrive:JobLive ./videos

echo "স্ট্রিমিং লুপ শুরু..."
while [ $(date +%s) -lt $END_TIME ]; do
    for video in ./videos/*.mp4; do
        if [ ! -f "$video" ]; then continue; fi
        
        REMAINING_TIME=$(( END_TIME - $(date +%s) ))
        
        if [ $REMAINING_TIME -le 0 ]; then
            echo "⏳ নির্ধারিত সময় পূর্ণ হয়েছে! লাইভ স্ট্রিমটি বন্ধ করা হচ্ছে..."
            exit 0
        fi

        echo "▶ এখন প্লে হচ্ছে: $video"
        timeout $REMAINING_TIME ffmpeg -re -i "$video" -c copy -f flv "rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_STREAM_KEY"
    done
done
