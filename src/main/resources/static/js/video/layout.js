const videoLayout = (() => {
    // 조회된 녹화 파일 뿌리기
    const recordList = (records) => {
        if (!records) return;

        const list = document.getElementById("recordingList");
        if (!list) return;

        list.innerHTML = records.map(record => {
            const date = new Date(record.createdDatetime);
            const formattedDate = `${date.getFullYear()}.${String(date.getMonth() + 1).padStart(2, "0")}.${String(date.getDate()).padStart(2, "0")}`;
            const formattedTime = `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
            const duration = record.recodingTime >= 60
                ? `${Math.floor(record.recodingTime / 60)}분 ${record.recodingTime % 60}초`
                : `${record.recodingTime}초`;

            return `
            <li class="recording-item" data-id="${record.id}" data-file-path="${record.filePath}">
                <div class="recording-info">
                    <span class="recording-date">${formattedDate} ${formattedTime}</span>
                    <span class="recording-duration">🕐 ${duration}</span>
                </div>
                <button class="summary-btn" data-id="${record.id}" data-file-path="${record.filePath}">
                    요약
                </button>
            </li>
        `;
        }).join("");

        list.querySelectorAll(".summary-btn").forEach(btn => {
            btn.addEventListener("click", async () => {
                const fileId = btn.dataset.id;
                const filePath = btn.dataset.filePath;

                btn.textContent = "요약 중...";
                btn.disabled = true;

                try {
                    const response = await fetch("/ai/video-chat/summation", {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        credentials: "include",
                        body: JSON.stringify({ fileId, filePath }),
                    });

                    if (!response.ok) throw new Error("요약 실패");

                    const data = await response.json();
                    console.log("요약 결과:", data);

                    btn.textContent = "요약 완료";

                } catch (error) {
                    console.error("요약 요청 실패:", error.message);
                    btn.textContent = "요약";
                    btn.disabled = false;
                }
            });
        });
    }

    return {
        recordList: recordList,
    };
})();