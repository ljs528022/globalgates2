const videoService = (() => {
    // 녹화 파일 저장
    const insertRecordFile = async (formData) => {
        const response = await fetch("/api/video-chat/recording", {
            method: "POST",
            body: formData,
            credentials: "include",
        });

        if (!response.ok) throw new Error("업로드 실패");

        const data = await response.json();
        console.log(data);
        console.log("녹화 파일 업로드 완료 - meetingId:", data.meetingId);
    }

    // 녹화 파일 조회
    const getRecords = async ({ opponentId }, callback) => {
        const params = new URLSearchParams({ opponentId });
        const response = await fetch(`/api/video-chat/list?${params}`, {
            credentials: "include",
        });

        if (!response.ok) throw new Error("불러오기 실패");

        const records = await response.json();

        if(callback) callback(records);
    }
    
    // 녹화 파일 요약 요청
    async function getSummary({ fileId, filePath }) {
        const response = await fetch("/ai/video-chat/summation", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            credentials: "include",
            body: JSON.stringify({ fileId, filePath }),
        });
        if (!response.ok) throw new Error("요약 실패");
        return await response.json();
    }

    return {
        insertRecordFile: insertRecordFile,
        getRecords: getRecords,
        getSummary: getSummary

    };
})();