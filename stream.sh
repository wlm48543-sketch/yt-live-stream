#!/bin/bash

echo "Rclone কনফিগারেশন এবং ফোল্ডার সেটআপ..."
mkdir -p ~/.config/rclone
echo "$RCLONE_CONFIG_DATA" > ~/.config/rclone/rclone.conf
mkdir -p ./videos

# ৩ ঘণ্টা (১০৮০০ সেকেন্ড) রান করার লিমিট
END_TIME=$(( $(date +%s) + 10800 ))

echo "গুগল ড্রাইভ থেকে ভিডিও সিঙ্ক করা হচ্ছে..."
rclone sync gdrive:JobLive ./videos

echo "পূর্ববর্তী জবের স্ট্যাটাস চেক করা হচ্ছে (Auto-Wait)..."
while true; do
    ACTIVE_RUNS=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs?status=in_progress" | jq '.total_count')

    if [ -z "$ACTIVE_RUNS" ] || [ "$ACTIVE_RUNS" -le 1 ]; then
        echo "✅ আগের কোনো জব নেই। স্ট্রিমিং শুরু হচ্ছে!"
        break
    fi
    echo "⏳ আগের জব এখনও চলছে... ৫ সেকেন্ড অপেক্ষা করা হচ্ছে।"
    sleep 5
done

echo "স্ট্রিমিং লুপ শুরু..."
while [ $(date +%s) -lt $END_TIME ]; do
    for video in ./videos/*.mp4; do
        if [ ! -f "$video" ]; then continue; fi
        
        # হাতে আর কতক্ষণ সময় বাকি আছে তা হিসাব করা হচ্ছে
        REMAINING_TIME=$(( END_TIME - $(date +%s) ))
        
        # যদি সময় শেষ হয়ে যায়, তবে স্ক্রিপ্ট সুন্দরভাবে বন্ধ হবে
        if [ $REMAINING_TIME -le 0 ]; then
            echo "⏳ ৩ ঘণ্টা পূর্ণ হয়েছে! নতুন জবের জন্য জায়গা ছেড়ে দিয়ে এটি বন্ধ করা হচ্ছে..."
            exit 0
        fi

        echo "▶ এখন প্লে হচ্ছে: $video"
        
        # timeout কমান্ড ব্যবহার করে ঠিক সময়মতো ভিডিও প্লে করা বন্ধ করা
        timeout $REMAINING_TIME ffmpeg -re -i "$video" -c copy -f flv "rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_STREAM_KEY"
    done
done
