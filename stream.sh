# --- ৩. স্ট্রিমিং এবং র‍্যান্ডম টাইমার লজিক ---
RANDOM_DURATION=$(( (RANDOM % 7201) + 10800 ))
HOURS=$(( RANDOM_DURATION / 3600 ))
MINUTES=$(( (RANDOM_DURATION % 3600) / 60 ))
echo "✅ এই লাইভ স্ট্রিমটি চলবে: $HOURS ঘণ্টা $MINUTES মিনিট ($RANDOM_DURATION সেকেন্ড)"

END_TIME=$(( $(date +%s) + RANDOM_DURATION ))

echo "গুগল ড্রাইভ থেকে ভিডিও সিঙ্ক করা হচ্ছে..."
rclone sync gdrive:JobLive ./videos

# চেক করা হচ্ছে ভিডিও ডাউনলোড হয়েছে কি না
VIDEO_COUNT=$(ls -1 ./videos/*.mp4 2>/dev/null | wc -l)
if [ "$VIDEO_COUNT" -eq 0 ]; then
    echo "❌ ত্রুটি: ./videos ফোল্ডারে কোনো .mp4 ভিডিও পাওয়া যায়নি! Rclone কনফিগারেশন বা গুগল ড্রাইভ ফোল্ডার চেক করুন।"
    exit 1
fi

echo "✅ মোট $VIDEO_COUNT টি ভিডিও পাওয়া গেছে। স্ট্রিমিং লুপ শুরু হচ্ছে..."

while [ $(date +%s) -lt $END_TIME ]; do
    for video in ./videos/*.mp4; do
        if [ ! -f "$video" ]; then continue; fi
        
        REMAINING_TIME=$(( END_TIME - $(date +%s) ))
        
        if [ $REMAINING_TIME -le 30 ]; then
            echo "⏳ নির্ধারিত সময় প্রায় পূর্ণ হয়েছে! লাইভ স্ট্রিম বন্ধ করা হচ্ছে..."
            exit 0
        fi

        echo "▶ এখন প্লে হচ্ছে: $video (বাকি সময়: $REMAINING_TIME সেকেন্ড)"
        
        # সুরক্ষিত FFmpeg কমান্ড (ভিডিও কপি, অডিও aac ফরম্যাটে এনকোড যাতে ইউটিউব রিজেক্ট না করে)
        timeout "$REMAINING_TIME" ffmpeg -re -i "$video" -c:v copy -c:a aac -b:a 128k -ar 44100 -f flv "rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_STREAM_KEY"
        
        FFMPEG_STATUS=$?
        if [ $FFMPEG_STATUS -ne 0 ] && [ $FFMPEG_STATUS -ne 124 ]; then
            echo "⚠️ FFmpeg ত্রুটি দিয়ে বন্ধ হয়েছে (Code: $FFMPEG_STATUS)। ৫ সেকেন্ড অপেক্ষা করে আবার চেষ্টা করা হচ্ছে..."
            sleep 5
        fi
    done
done
