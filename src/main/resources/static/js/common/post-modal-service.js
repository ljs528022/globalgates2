// 공용 모달 전용 service — 가입 커뮤니티 조회 + 커뮤니티 게시 endpoint 호출 + 토스트
const postModalService = (() => {

    const getMyCommunities = async (page = 1) => {
        const res = await fetch(`/api/communities/my/${page}`);
        return await res.json();
    };

    const writeCommunityPost = async (communityId, formData) => {
        await fetch(`/api/communities/${communityId}/posts`, { method: "POST", body: formData });
    };

    // 게시 후 자동 토스트 — main의 .notification-toast 클래스 재사용
    const showToast = (message) => {
        const existing = document.querySelector(".notification-toast");
        if (existing) existing.remove();
        const toast = document.createElement("div");
        toast.className = "notification-toast";
        toast.textContent = message;
        document.body.appendChild(toast);
        setTimeout(() => toast.remove(), 3000);
    };

    // AI 게시글 내용 신뢰도 측정
    const calcTrustScore = async (text) => {
        const response = await fetch('/ai/post/trust', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text }),
        });

        const data = await response.json();
        console.log(data);

        if (!response.ok) throw new Error('신뢰도 분석 요청 실패');
        return data.score;   // { score: 0 | 1 | 2 }
    };

    return { getMyCommunities, writeCommunityPost, showToast, calcTrustScore };
})();
