#!/bin/bash

echo "======================================================"
echo "১. Rclone কনফিগারেশন এবং ভিডিও ডাউনলোড..."
echo "======================================================"
mkdir -p ~/.config/rclone
echo "$RCLONE_CONFIG_DATA" > ~/.config/rclone/rclone.conf
mkdir -p ./videos

echo "গুগল ড্রাইভ থেকে ভিডিও সিঙ্ক করা হচ্ছে..."
rclone sync gdrive:JobLive ./videos

VIDEO_COUNT=$(find ./videos -maxdepth 1 -name "*.mp4" | wc -l)
if [ "$VIDEO_COUNT" -eq 0 ]; then
    echo "❌ ত্রুটি: ./videos ফোল্ডারে কোনো .mp4 ফাইল পাওয়া যায়নি!"
    exit 1
fi
echo "✅ সফলভাবে $VIDEO_COUNT টি ভিডিও পাওয়া গেছে।"

# --- ২. টাইটেল সিলেকশন এবং history.json আপডেট ---
echo "======================================================"
echo "২. টাইটেল নির্ধারণ..."
echo "======================================================"
if [ ! -f Tittles.txt ]; then
    echo "❌ Tittles.txt ফাইল পাওয়া যায়নি! ডিফল্ট টাইটেল ব্যবহার করা হবে।"
    CURRENT_TITLE="My 24/7 Live Stream"
else
    LAST_INDEX=$(jq -r '.last_index // 0' history.json 2>/dev/null || echo "0")
    TOTAL_TITLES=$(grep -c '[^[:space:]]' Tittles.txt)
    
    NEXT_INDEX=$((LAST_INDEX + 1))
    if [ "$NEXT_INDEX" -gt "$TOTAL_TITLES" ]; then
        NEXT_INDEX=1
    fi
    
    # উইন্ডোজের \r ক্যারেক্টার ক্লিন করে নেওয়া
    CURRENT_TITLE=$(sed "${NEXT_INDEX}q;d" Tittles.txt | tr -d '\r\n')
    echo "✅ নির্বাচিত টাইটেল (Index $NEXT_INDEX): $CURRENT_TITLE"
    
    echo "{\"last_index\": $NEXT_INDEX}" > history.json
    git config --global user.name "github-actions[bot]"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"
    git add history.json
    git commit -m "Auto-update title index to $NEXT_INDEX"
    git push || echo "⚠️ গিটহাবে পুশ করতে সমস্যা হয়েছে, তবে লাইভ চলবে।"
fi

# --- ৩. YouTube API দিয়ে নতুন ব্রডকাস্ট তৈরি এবং একই কি-এর সাথে লিঙ্ক করা ---
echo "======================================================"
echo "৩. YouTube API: অটো-ব্রডকাস্ট তৈরি এবং লাইভ রুম রেডি করা..."
echo "======================================================"

TOKEN_RESPONSE=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "refresh_token=$REFRESH_TOKEN" \
  -d "grant_type=refresh_token")
  
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r .access_token)

if [ "$ACCESS_TOKEN" != "null" ] && [ -n "$ACCESS_TOKEN" ]; then
    echo "✅ Access Token সফলভাবে জেনারেট হয়েছে।"

    # আপনার অ্যাকাউন্টের Stream ID বের করা (যাতে同一个 কি-এর সাথে লিঙ্ক করা যায়)
    STREAMS_LIST=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
      "https://www.googleapis.com/youtube/v3/liveStreams?part=id,cdn&mine=true")
      
    STREAM_ID=$(echo "$STREAMS_LIST" | jq -r --arg key "$YOUTUBE_STREAM_KEY" \
      '.items[] | select(.cdn.ingestionInfo.streamName == $key) | .id' | head -n 1)

    # যদি কী দিয়ে সরাসরি না পায় তবে ডিফল্ট প্রথম স্ট্রিম আইডি ব্যবহার করবে
    if [ -z "$STREAM_ID" ] || [ "$STREAM_ID" == "null" ]; then
        STREAM_ID=$(echo "$STREAMS_LIST" | jq -r '.items[0].id // empty')
    fi
    
    echo "✅ আপনার চ্যানেলের মূল Stream ID: $STREAM_ID"

    if [ -n "$STREAM_ID" ]; then
        START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        
        # বর্তমান টাইটেল ও Auto-Start/Auto-Stop এনাবল করে ব্রডকাস্ট পেলোড তৈরি
        BROADCAST_PAYLOAD=$(jq -n \
          --arg title "$CURRENT_TITLE" \
          --arg desc "সরাসরি বিস্তারিত আলোচনা চলমান সকল চাকরির খবর ও আবেদনের বিস্তারিত" \
          --arg time "$START_TIME" \
          '{
            snippet: {
              title: $title,
              description: $desc,
              scheduledStartTime: $time
            },
            status: {
              privacyStatus: "public",
              selfDeclaredMadeForKids: false
            },
            contentDetails: {
              enableAutoStart: true,
              enableAutoStop: true,
              recordFromStart: true
            }
          }')

        # নতুন ব্রডকাস্ট তৈরি
        CREATE_RES=$(curl -s -X POST "https://www.googleapis.com/youtube/v3/liveBroadcasts?part=snippet,status,contentDetails" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json" \
          -d "$BROADCAST_PAYLOAD")

        BROADCAST_ID=$(echo "$CREATE_RES" | jq -r '.id // empty')

        if [ -n "$BROADCAST_ID" ] && [ "$BROADCAST_ID" != "null" ]; then
            echo "🎉 নতুন ব্রডকাস্ট তৈরি হয়েছে! ID: $BROADCAST_ID"
            
            # তৈরি হওয়া ব্রডকাস্টকে আপনার ফিক্সড Stream Key-এর সাথে লিঙ্ক (Bind) করা
            BIND_RES=$(curl -s -X POST \
              "https://www.googleapis.com/youtube/v3/liveBroadcasts/bind?id=$BROADCAST_ID&part=id,contentDetails&streamId=$STREAM_ID" \
              -H "Authorization: Bearer $ACCESS_TOKEN" \
              -H "Content-Type: application/json")

            echo "🔗 ব্রডকাস্ট এবং আপনার ফিক্সড Stream Key সফলভাবে যুক্ত (Bind) হয়েছে!"
            echo "⚡ ইউটিউব এখন ভিডিও ডেটা পাওয়ার সাথে সাথেই স্বয়ংক্রিয়ভাবে লাইভ শুরু করে দেবে।"
        else
            echo "⚠️ নতুন ব্রডকাস্ট তৈরিতে সমস্যা হয়েছে। ডিফল্ট ব্রডকাস্ট দিয়ে চেষ্টা করা হচ্ছে..."
        fi
    fi
else
    echo "⚠️ Access Token পাওয়া যায়নি, ডিফল্ট স্ট্রিমে পুশ করা হবে।"
fi

# --- ৪. স্ট্রিমিং এবং র‍্যান্ডম টাইমার লজিক ---
echo "======================================================"
echo "৪. স্ট্রিমিং শুরু হচ্ছে..."
echo "======================================================"
RANDOM_DURATION=$(( (RANDOM % 7201) + 10800 ))
HOURS=$(( RANDOM_DURATION / 3600 ))
MINUTES=$(( (RANDOM_DURATION % 3600) / 60 ))
echo "✅ এই লাইভ সেশনটি চলবে: $HOURS ঘণ্টা $MINUTES মিনিট ($RANDOM_DURATION সেকেন্ড)"

END_TIME=$(( $(date +%s) + RANDOM_DURATION ))

while [ $(date +%s) -lt $END_TIME ]; do
    for video in ./videos/*.mp4; do
        if [ ! -f "$video" ]; then continue; fi
        
        REMAINING_TIME=$(( END_TIME - $(date +%s) ))
        
        if [ $REMAINING_TIME -le 30 ]; then
            echo "⏳ নির্ধারিত সময় শেষ! লাইভ স্ট্রিমটি বন্ধ করা হচ্ছে..."
            exit 0
        fi

        echo "▶ এখন প্লে হচ্ছে: $video (বাকি সময়: $REMAINING_TIME সেকেন্ড)"
        
        # সুরক্ষিত FFmpeg কমান্ড
        timeout "$REMAINING_TIME" ffmpeg -re -i "$video" -c:v copy -c:a aac -b:a 128k -ar 44100 -f flv "rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_STREAM_KEY"
        
        FFMPEG_EXIT=$?
        if [ $FFMPEG_EXIT -ne 0 ] && [ $FFMPEG_EXIT -ne 124 ]; then
            echo "⚠️ FFmpeg ডিসকানেক্ট হয়েছে (Code: $FFMPEG_EXIT)। ৫ সেকেন্ড বিরতি..."
            sleep 5
        fi
    done
done

echo "লাইভ স্ট্রিম সেশন সফলভাবে সম্পন্ন হয়েছে।"
exit 0
