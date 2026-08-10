#!/bin/bash

echo "Rclone কনফিগারেশন এবং ফোল্ডার সেটআপ করা হচ্ছে..."
mkdir -p ~/.config/rclone
echo "$RCLONE_CONFIG_DATA" > ~/.config/rclone/rclone.conf
mkdir -p ./videos

# ৩ ঘণ্টা (১০৮০০ সেকেন্ড) রান করার লিমিট
END_TIME=$(( $(date +%s) + 10800 ))

echo "গুগল ড্রাইভ থেকে ভিডিও সিঙ্ক করা হচ্ছে..."
# (আপনার ড্রাইভের নাম gdrive এবং ফোল্ডার videos হলে এটি এভাবেই রাখুন)
rclone sync gdrive:JobLive ./videos

echo "পূর্ববর্তী জবের স্ট্যাটাস চেক করা হচ্ছে (Auto-Wait)..."
while true; do
    # গিটহাব API দিয়ে চেক করা হচ্ছে কয়টি জব বর্তমানে রান করছে
    ACTIVE_RUNS=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs?status=in_progress" | jq '.total_count')

    # যদি ACTIVE_RUNS 1 হয়, তার মানে শুধু এই জবটিই চলছে, আগেরটি বন্ধ হয়ে গেছে
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
        
        echo "▶ এখন প্লে হচ্ছে: $video"
        ffmpeg -re -i "$video" -c copy -f flv "rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_STREAM_KEY"
        
        # প্রতিটি ভিডিও প্লে হওয়ার পর চেক করবে ৩ ঘণ্টা পার হয়েছে কি না
        if [ $(date +%s) -ge $END_TIME ]; then
            echo "⏳ ৩ ঘণ্টা পূর্ণ হয়েছে! নতুন জবের জন্য জায়গা ছেড়ে দিয়ে এটি বন্ধ করা হচ্ছে..."
            exit 0
        fi
    done
done
