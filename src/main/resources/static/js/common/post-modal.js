// 게시물 작성/수정 모달 + 답글 모달 통합 모듈. main/event.js 의 모달 로직을 단계적으로 이쪽으로 옮긴다.

const postModalApi = (() => {
    // 외부 의존(services/layout)은 init() 시점 주입, memberId 는 호출 시점에 getter 로 받는다.
    let _services = null;
    let _layout = null;

    function init(options) {
        const opts = options || {};
        _services = opts.services || _services;
        _layout = opts.layout || _layout;
    }

    // @ 입력 → 멘션 드롭다운. 작성/답글 양쪽 에디터에서 공유 사용.
    function setupMention(editor, dropdownContainer, getMemberId) {
        console.log("멘션셋업 들어옴1");
        let mentionMode = false;
        let mentionQuery = '';
        let mentionActiveIndex = 0;
        let mentionResults = [];

        const dropdown = document.createElement('div');
        dropdown.className = 'mention-dropdown off';
        document.body.appendChild(dropdown);

        editor.addEventListener('input', async () => {
            const sel = window.getSelection();
            if (!sel.rangeCount) return;
            const range = sel.getRangeAt(0);
            const textNode = range.startContainer;
            if (textNode.nodeType !== Node.TEXT_NODE) { closeMentionDropdown(); return; }

            const text = textNode.textContent;
            const cursorPos = range.startOffset;
            const beforeCursor = text.substring(0, cursorPos);
            const atIndex = beforeCursor.lastIndexOf('@');

            if (atIndex === -1 || (atIndex > 0 && beforeCursor[atIndex - 1] !== ' ' && beforeCursor[atIndex - 1] !== '\n')) {
                closeMentionDropdown(); return;
            }

            const query = beforeCursor.substring(atIndex + 1);
            if (query.includes(' ')) { closeMentionDropdown(); return; }

            mentionMode = true;
            mentionQuery = query;
            console.log("멘션모드 들어옴1 query:", query);

            if (query.length === 0) { closeMentionDropdown(); return; }

            const members = await _services.searchMentionMembers(query, getMemberId());
            mentionResults = members;
            mentionActiveIndex = 0;

            if (members.length === 0) { closeMentionDropdown(); return; }

            dropdown.innerHTML = _layout.buildMentionDropdown(members);
            // 입력중인 줄 기준으로 드롭다운 표시
            const cursorRect = range.getBoundingClientRect();
            const editorRect = editor.getBoundingClientRect();
            dropdown.style.left = editorRect.left + 'px';
            dropdown.style.top = (cursorRect.bottom + 4) + 'px';
            dropdown.style.bottom = 'auto';
            dropdown.classList.remove('off');
            console.log("멘션드롭다운 들어옴2 열림");

            dropdown.querySelectorAll('.mention-item').forEach((item, idx) => {
                item.addEventListener('mousedown', (e) => { e.preventDefault(); selectMention(idx); });
            });
        });

        editor.addEventListener('keydown', (e) => {
            if (!mentionMode || dropdown.classList.contains('off')) return;
            if (e.key === 'ArrowDown') { e.preventDefault(); mentionActiveIndex = Math.min(mentionActiveIndex + 1, mentionResults.length - 1); updateActiveItem(); }
            else if (e.key === 'ArrowUp') { e.preventDefault(); mentionActiveIndex = Math.max(mentionActiveIndex - 1, 0); updateActiveItem(); }
            else if (e.key === 'Enter') { e.preventDefault(); selectMention(mentionActiveIndex); }
            else if (e.key === 'Escape') { closeMentionDropdown(); }
        });

        function updateActiveItem() {
            dropdown.querySelectorAll('.mention-item').forEach((item, idx) => {
                item.classList.toggle('active', idx === mentionActiveIndex);
                if (idx === mentionActiveIndex) item.scrollIntoView({ block: 'nearest' });
            });
        }

        function selectMention(index) {
            console.log("멘션선택 들어옴1 index:", index);
            const member = mentionResults[index];
            if (!member) return;
            const sel = window.getSelection();
            if (!sel.rangeCount) return;
            const range = sel.getRangeAt(0);
            const textNode = range.startContainer;
            if (textNode.nodeType !== Node.TEXT_NODE) return;

            const text = textNode.textContent;
            const cursorPos = range.startOffset;
            const beforeCursor = text.substring(0, cursorPos);
            const atIndex = beforeCursor.lastIndexOf('@');
            const before = text.substring(0, atIndex);
            const after = text.substring(cursorPos);

            textNode.textContent = before;

            const mentionSpan = document.createElement('span');
            mentionSpan.className = 'mention-tag';
            mentionSpan.contentEditable = 'false';
            mentionSpan.dataset.handle = member.memberHandle;
            mentionSpan.dataset.memberId = member.id;
            mentionSpan.textContent = member.memberHandle;

            const afterNode = document.createTextNode(' ' + after);
            const parent = textNode.parentNode;
            const nextSibling = textNode.nextSibling;
            parent.insertBefore(mentionSpan, nextSibling);
            parent.insertBefore(afterNode, mentionSpan.nextSibling);

            const newRange = document.createRange();
            newRange.setStart(afterNode, 1);
            newRange.collapse(true);
            sel.removeAllRanges();
            sel.addRange(newRange);

            closeMentionDropdown();
            console.log("멘션선택 들어옴2 완료:", member.memberHandle);
            editor.dispatchEvent(new Event('input', { bubbles: true }));
        }

        function closeMentionDropdown() {
            mentionMode = false;
            mentionQuery = '';
            mentionResults = [];
            dropdown.classList.add('off');
            dropdown.innerHTML = '';
        }

        return { closeMentionDropdown };
    }

    // 에디터 안의 .mention-tag 들로부터 핸들 목록을 모은다.
    function collectMentionHandles(editor) {
        const mentions = editor.querySelectorAll('.mention-tag');
        const handles = [];
        mentions.forEach((m) => {
            const handle = m.dataset.handle;
            if (handle && !handles.includes(handle)) handles.push(handle);
        });
        console.log("멘션수집 들어옴1 handles:", handles);
        return handles;
    }

    // 작성/답글 모달의 모든 서브뷰(태그/카테고리/위치/판매글/임시저장/포맷/이모지/파일첨부) 통합 셋업.
    function setupSubViews(overlay, getMemberId) {
        const composeView = overlay.querySelector(".tweet-modal__compose-view");
        const locationView = overlay.querySelector(".tweet-modal__location-view");
        const tagView = overlay.querySelector(".tweet-modal__tag-view");
        const mediaView = overlay.querySelector(".tweet-modal__media-view");
        const postTempView = overlay.querySelector(".tweet-modal__draft-view");
        const productView = overlay.querySelector(".tweet-modal__product-view");

        const allSubViews = [locationView, tagView, mediaView, postTempView, productView];

        function showSubView(view) {
            composeView.classList.add("off");
            for (let i = 0; i < allSubViews.length; i++) {
                if (allSubViews[i]) { allSubViews[i].classList.add("off"); }
            }
            if (view) { view.classList.remove("off"); }
        }

        function backToCompose() {
            for (let i = 0; i < allSubViews.length; i++) {
                if (allSubViews[i]) { allSubViews[i].classList.add("off"); }
            }
            composeView.classList.remove("off");
        }

        // 대상 선택 (일반 / 가입 커뮤니티) — boardMenu 토글 + lazy fetch + 이벤트 위임
        const audienceBtn = overlay.querySelector(".audienceButton");
        const boardMenu = document.getElementById("boardMenu");
        const communityMenuList = document.getElementById("communityMenuList");
        let communitiesLoaded = false;

        async function loadMyCommunities() {
            if (communitiesLoaded || !communityMenuList) return;
            try {
                const data = await postModalService.getMyCommunities(1);
                const communities = data.communities || [];
                if (communities.length > 0) {
                    communityMenuList.innerHTML = "";
                    communities.forEach(c => {
                        const item = document.createElement("div");
                        item.className = "communityMenuItem";
                        item.dataset.communityId = c.id;
                        const name = document.createElement("span");
                        name.className = "communityMenuName";
                        name.textContent = c.communityName;
                        item.appendChild(name);
                        communityMenuList.appendChild(item);
                    });
                }
                communitiesLoaded = true;
            } catch (err) {
                console.error("가입 커뮤니티 로딩 실패:", err);
            }
        }

        if (audienceBtn && boardMenu) {
            audienceBtn.addEventListener("click", async (e) => {
                e.stopPropagation();
                const isOpen = !boardMenu.classList.contains("off");
                if (isOpen) {
                    boardMenu.classList.add("off");
                    return;
                }
                await loadMyCommunities();
                const rect = audienceBtn.getBoundingClientRect();
                boardMenu.style.left = rect.left + "px";
                boardMenu.style.top = (rect.bottom + 8) + "px";
                boardMenu.classList.remove("off");
            });

            // 이벤트 위임: 일반 옵션 + 동적 커뮤니티 항목 모두 처리
            boardMenu.addEventListener("click", (e) => {
                const generalOpt = e.target.closest('[data-target="general"]');
                const communityOpt = e.target.closest(".communityMenuItem");
                const target = generalOpt || communityOpt;
                if (!target) return;
                boardMenu.querySelectorAll(".boardMenuOption, .communityMenuItem")
                    .forEach(el => el.classList.remove("isSelected"));
                target.classList.add("isSelected");
                if (generalOpt) {
                    audienceBtn.textContent = "일반";
                    delete audienceBtn.dataset.communityId;
                } else {
                    audienceBtn.textContent = communityOpt.querySelector(".communityMenuName").textContent;
                    audienceBtn.dataset.communityId = communityOpt.dataset.communityId;
                }
                boardMenu.classList.add("off");
            });
        }

        // 태그 추가
        const tagToggle = overlay.querySelector(".composerTagLabel");
        const tagEditor = overlay.querySelector(".composerTagEditor");
        const tagField = overlay.querySelector(".composerTagField");
        const tagDock = overlay.querySelector(".composerAudienceTagDock");
        const tagInput = overlay.querySelector(".tag-input");
        const specialCharRegex = /[\{\}\[\]\?.,;:|\)*~`!^\-_+<>@\#$%&\\=\(\'\"]/;
        let isTagEditorOpen = false;

        function getTagDivs() {
            if (!tagInput) { return []; }
            const nodes = tagInput.querySelectorAll(".tagDiv");
            let result = [];
            for (let i = 0; i < nodes.length; i++) { result.push(nodes[i]); }
            return result;
        }

        function syncTagUI() {
            if (!tagToggle || !tagEditor) { return; }
            const hasTags = getTagDivs().length > 0;
            tagEditor.classList.toggle("off", !isTagEditorOpen);
            if (tagInput) { tagInput.classList.toggle("off", !hasTags); }
            if (isTagEditorOpen) {
                tagToggle.textContent = "태그 닫기";
            } else {
                tagToggle.textContent = "태그 추가";
                if (tagField) { tagField.value = ""; }
            }
        }

        function addTag(rawTag, fromProduct) {
            const tag = (rawTag || "").trim();
            if (!tag) { return false; }
            if (getTagDivs().length >= 5) { alert("태그는 최대 5개까지 추가할 수 있어요"); if (tagField) { tagField.value = ""; } return false; }
            if (specialCharRegex.test(tag)) { alert("특수문자는 입력 못해요"); if (tagField) { tagField.value = ""; } return false; }
            const existing = getTagDivs();
            for (let i = 0; i < existing.length; i++) {
                if (existing[i].textContent === "#" + tag) { alert("중복된 태그가 있어요"); if (tagField) { tagField.value = ""; } return false; }
            }
            const span = document.createElement("span");
            span.className = "tagDiv";
            if (fromProduct) { span.setAttribute("data-from-product", "true"); }
            span.textContent = "#" + tag;
            if (tagInput) { tagInput.appendChild(span); }
            if (tagField) { tagField.value = ""; }
            isTagEditorOpen = false;
            syncTagUI();
            return true;
        }

        if (tagToggle) {
            tagToggle.addEventListener("click", (e) => {
                isTagEditorOpen = !isTagEditorOpen;
                syncTagUI();
                if (isTagEditorOpen && tagField) { tagField.focus(); }
            });
        }
        if (tagField) {
            tagField.addEventListener("keyup", (e) => {
                if (e.key === "Enter" && tagField.value) { e.preventDefault(); addTag(tagField.value); }
                if (e.key === "Escape") { isTagEditorOpen = false; syncTagUI(); if (tagToggle) { tagToggle.focus(); } }
            });
            tagField.addEventListener("focus", (e) => { isTagEditorOpen = true; syncTagUI(); });
        }
        if (tagInput) {
            tagInput.addEventListener("click", (e) => {
                if (e.target.classList.contains("tagDiv")) { e.target.remove(); syncTagUI(); }
            });
        }

        // 카테고리 칩 + 스크롤
        const catScroll = overlay.querySelector(".category-scroll");
        const catLeft = overlay.querySelector(".category-scroll-left");
        const catRight = overlay.querySelector(".category-scroll-right");
        let originalChipsHTML = catScroll ? catScroll.innerHTML : "";

        function checkCatScroll() {
            if (!catScroll || !catLeft || !catRight) { return; }
            catLeft.classList.toggle("off", catScroll.scrollLeft <= 0);
            catRight.classList.toggle("off", catScroll.scrollLeft >= catScroll.scrollWidth - catScroll.clientWidth - 1);
        }

        if (catScroll) {
            catScroll.addEventListener("scroll", (e) => { checkCatScroll(); });
            catScroll.addEventListener("click", (e) => {
                const chip = e.target.closest(".cat-chip");
                const backBtn = e.target.closest(".cat-back-btn");
                if (backBtn) { catScroll.innerHTML = originalChipsHTML; catScroll.scrollLeft = 0; setTimeout(checkCatScroll, 50); return; }
                if (!chip) { return; }
                if (chip.classList.contains("has-subs")) {
                    const catName = chip.textContent.replace(" ›", "");
                    const subs = chip.getAttribute("data-subs");
                    if (!subs) { return; }
                    const subList = subs.split(",");
                    let html = '<button type="button" class="cat-back-btn"><svg viewBox="0 0 24 24"><path d="M12 4l-1.41 1.41L16.17 11H4v2h12.17l-5.58 5.59L12 20l8-8z" transform="rotate(180 12 12)" fill="currentColor"/></svg></button>';
                    html += '<button type="button" class="cat-chip parent-highlight">' + catName + '</button>';
                    for (let i = 0; i < subList.length; i++) { html += '<button type="button" class="cat-chip" data-is-sub="true">' + subList[i] + '</button>'; }
                    catScroll.innerHTML = html;
                    catScroll.scrollLeft = 0;
                    setTimeout(checkCatScroll, 50);
                    return;
                }
                const chipText = chip.textContent.trim();
                if (chipText === "전체") { return; }
                addTag(chipText);
                const allChips = catScroll.querySelectorAll(".cat-chip:not(.parent-highlight)");
                for (let i = 0; i < allChips.length; i++) { allChips[i].classList.remove("active", "sub-active"); }
                if (chip.getAttribute("data-is-sub")) { chip.classList.add("sub-active"); } else { chip.classList.add("active"); }
            });
        }
        if (catLeft) { catLeft.addEventListener("click", (e) => { catScroll.scrollBy({ left: -200, behavior: "smooth" }); }); }
        if (catRight) { catRight.addEventListener("click", (e) => { catScroll.scrollBy({ left: 200, behavior: "smooth" }); }); }
        checkCatScroll();

        // 임시저장
        const postTempBtn = overlay.querySelector(".tweet-modal__draft");
        const postTempList = postTempView ? postTempView.querySelector(".draft-panel__list") : null;
        const postTempEmpty = postTempView ? postTempView.querySelector(".draft-panel__empty") : null;
        const postTempFooter = postTempView ? postTempView.querySelector(".draft-panel__footer") : null;
        const postTempSelectAll = postTempView ? postTempView.querySelector(".draft-panel__select-all") : null;
        const postTempFooterDelete = postTempView ? postTempView.querySelector(".draft-panel__footer-delete") : null;
        const postTempConfirmOverlay = postTempView ? postTempView.querySelector(".draft-panel__confirm-overlay") : null;
        const postTempConfirmPrimary = postTempConfirmOverlay ? postTempConfirmOverlay.querySelector(".draft-panel__confirm-primary") : null;
        const postTempConfirmSecondary = postTempConfirmOverlay ? postTempConfirmOverlay.querySelector(".draft-panel__confirm-secondary") : null;
        const modalEditor = overlay.querySelector(".tweet-modal__editor");
        let postTemps = [];
        let selectedPostTempIndexes = [];

        async function loadPostTemps() {
            postTemps = await _services.getPostTemps(getMemberId());
            console.log("목록들어옴", postTemps.length, postTemps);
        }

        function updatePostTempFooter() {
            if (!postTempFooter) { return; }
            postTempFooter.classList.toggle("off", postTemps.length === 0);
            if (postTempFooterDelete) { postTempFooterDelete.disabled = selectedPostTempIndexes.length === 0; }
            if (postTempSelectAll) { postTempSelectAll.textContent = (postTemps.length > 0 && selectedPostTempIndexes.length === postTemps.length) ? "전체 해제" : "모두 선택"; }
        }

        function isSelected(idx) { for (let i = 0; i < selectedPostTempIndexes.length; i++) { if (selectedPostTempIndexes[i] === idx) { return true; } } return false; }
        function togglePostTempSelect(idx) {
            if (isSelected(idx)) { let next = []; for (let i = 0; i < selectedPostTempIndexes.length; i++) { if (selectedPostTempIndexes[i] !== idx) { next.push(selectedPostTempIndexes[i]); } } selectedPostTempIndexes = next; }
            else { selectedPostTempIndexes.push(idx); }
            syncPostTempCheckboxes(); updatePostTempFooter();
        }

        function syncPostTempCheckboxes() {
            if (!postTempList) { return; }
            const items = postTempList.querySelectorAll(".draft-panel__item");
            for (let i = 0; i < items.length; i++) {
                const idx = parseInt(items[i].getAttribute("data-draft-index"));
                const cb = items[i].querySelector(".draft-panel__item-checkbox");
                if (isSelected(idx)) { items[i].classList.add("draft-panel__item--selected"); if (cb) { cb.checked = true; } }
                else { items[i].classList.remove("draft-panel__item--selected"); if (cb) { cb.checked = false; } }
            }
        }

        function renderPostTempList() {
            console.log("목록그림 개수:", postTemps.length);
            selectedPostTempIndexes = [];
            if (!postTempList) { return; }
            if (postTemps.length === 0) { postTempList.innerHTML = ""; if (postTempEmpty) { postTempEmpty.classList.remove("off"); } updatePostTempFooter(); return; }
            if (postTempEmpty) { postTempEmpty.classList.add("off"); }
            let html = "";
            for (let i = 0; i < postTemps.length; i++) {
                const d = postTemps[i];
                html += '<div class="draft-panel__item" data-draft-index="' + i + '" data-draft-id="' + d.id + '"><input type="checkbox" class="draft-panel__item-checkbox" data-draft-check="' + i + '" /><button type="button" class="draft-panel__item-load" data-draft-load="' + i + '"><span class="draft-panel__item-body"><span class="draft-panel__text">' + d.postTempContent + '</span><span class="draft-panel__date">' + (d.createdDatetime || "") + '</span></span></button><span class="draft-panel__item-delete" data-draft-delete="' + i + '">✕</span></div>';
            }
            postTempList.innerHTML = html;
            updatePostTempFooter();
        }

        async function savePostTempFromEditor() {
            if (!modalEditor) { return; }
            const text = modalEditor.textContent.trim();
            if (!text) { return; }
            const tempLocation = selectedLocation || null;
            const tagDivs = getTagDivs();
            const tempTags = tagDivs.length > 0 ? JSON.stringify(tagDivs.map(t => t.textContent.replace("#", ""))) : null;
            console.log("임시저장함 내용:", text, "위치:", tempLocation, "태그:", tempTags);
            await _services.savePostTemp(getMemberId(), text, tempLocation, tempTags);
            await loadPostTemps();
        }

        async function loadPostTempToEditor(index) {
            console.log("목록불러옴 index:", index, "id:", postTemps[index]?.id);
            if (!modalEditor || !postTemps[index]) { return; }
            const loaded = await _services.loadPostTemp(postTemps[index].id);
            console.log("목록가져옴 내용:", loaded.postTempContent, "위치:", loaded.postTempLocation, "태그:", loaded.postTempTags);
            modalEditor.textContent = loaded.postTempContent;

            // 기존 태그 초기화 후 복원
            const oldTags = getTagDivs();
            for (let i = 0; i < oldTags.length; i++) { oldTags[i].remove(); }
            if (loaded.postTempTags) {
                JSON.parse(loaded.postTempTags).forEach(tag => addTag(tag));
            }
            syncTagUI();

            // 위치 복원
            selectedLocation = loaded.postTempLocation || null;
            updateLocationUI();

            postTemps.splice(index, 1);
            modalEditor.dispatchEvent(new Event("input"));
            backToCompose();
        }

        if (postTempBtn && postTempView) {
            postTempBtn.addEventListener("click", async (e) => {
                if (modalEditor && modalEditor.textContent.trim()) {
                    await savePostTempFromEditor(); modalEditor.innerHTML = "";
                    modalEditor.dispatchEvent(new Event("input"));
                    // 태그/위치 초기화
                    const oldTags = getTagDivs();
                    for (let i = 0; i < oldTags.length; i++) { oldTags[i].remove(); }
                    syncTagUI();
                    selectedLocation = null;
                    updateLocationUI();
                }
                await loadPostTemps();
                renderPostTempList();
                showSubView(postTempView);
            });
        }
        const postTempBack = postTempView ? postTempView.querySelector(".draft-panel__back") : null;
        if (postTempBack) { postTempBack.addEventListener("click", (e) => { backToCompose(); }); }
        let pendingDeleteIndexes = [];

        if (postTempList) {
            postTempList.addEventListener("click", (e) => {
                const checkbox = e.target.closest("[data-draft-check]");
                if (checkbox) { togglePostTempSelect(parseInt(checkbox.getAttribute("data-draft-check"))); return; }
                const deleteBtn = e.target.closest("[data-draft-delete]");
                if (deleteBtn) { pendingDeleteIndexes = [parseInt(deleteBtn.getAttribute("data-draft-delete"))]; if (postTempConfirmOverlay) { postTempConfirmOverlay.classList.remove("off"); } return; }
                const loadBtn = e.target.closest("[data-draft-load]");
                if (loadBtn) { loadPostTempToEditor(parseInt(loadBtn.getAttribute("data-draft-load"))); }
            });
        }
        if (postTempSelectAll) {
            postTempSelectAll.addEventListener("click", (e) => {
                if (selectedPostTempIndexes.length === postTemps.length) { selectedPostTempIndexes = []; }
                else { selectedPostTempIndexes = []; for (let i = 0; i < postTemps.length; i++) { selectedPostTempIndexes.push(i); } }
                syncPostTempCheckboxes(); updatePostTempFooter();
            });
        }
        if (postTempFooterDelete) {
            postTempFooterDelete.addEventListener("click", (e) => {
                if (selectedPostTempIndexes.length === 0) { return; }
                pendingDeleteIndexes = []; for (let i = 0; i < selectedPostTempIndexes.length; i++) { pendingDeleteIndexes.push(selectedPostTempIndexes[i]); }
                if (postTempConfirmOverlay) { postTempConfirmOverlay.classList.remove("off"); }
            });
        }
        if (postTempConfirmPrimary) {
            postTempConfirmPrimary.addEventListener("click", async (e) => {
                const idsToDelete = pendingDeleteIndexes.map(idx => postTemps[idx].id);
                await _services.deletePostTemps(idsToDelete);
                pendingDeleteIndexes = [];
                await loadPostTemps();
                if (postTempConfirmOverlay) { postTempConfirmOverlay.classList.add("off"); }
                renderPostTempList();
            });
        }
        if (postTempConfirmSecondary) { postTempConfirmSecondary.addEventListener("click", (e) => { if (postTempConfirmOverlay) { postTempConfirmOverlay.classList.add("off"); } }); }

        // 위치

        const geoBtn = overlay.querySelector(".tweet-modal__tool-btn--geo");
        const locationList = locationView ? locationView.querySelector("[data-location-list]") : null;
        const locationSearchInput = locationView ? locationView.querySelector("[data-location-search]") : null;
        const locationSearchBtn = locationView ? locationView.querySelector("[data-location-search-btn]") : null;
        const locationClose = locationView ? locationView.querySelector(".tweet-modal__location-close") : null;
        const locationDeleteBtn = locationView ? locationView.querySelector("[data-location-delete]") : null;
        const locationCompleteBtn = locationView ? locationView.querySelector("[data-location-complete]") : null;
        const locationDisplay = overlay.querySelector(".tweet-modal__location-display");
        const locationDisplayText = locationDisplay ? locationDisplay.querySelector(".tweet-modal__location-display-text-inner") : null;
        let selectedLocation = null;
        let ps = null;

        function updateLocationUI() {
            if (locationDisplay && locationDisplayText) {
                if (selectedLocation) { locationDisplayText.value = selectedLocation; locationDisplay.removeAttribute("hidden"); }
                else { locationDisplayText.value = ""; locationDisplay.setAttribute("hidden", ""); }
            }
            if (locationDeleteBtn) { locationDeleteBtn.hidden = !selectedLocation; }
            if (locationCompleteBtn) { locationCompleteBtn.disabled = !selectedLocation; }
        }

        function searchPlaces() {
            console.log("searchPlaces 호출됨");
            var keyword = locationSearchInput.value;
            console.log("keyword:", keyword);
            if (!keyword.replace(/^\s+|\s+$/g, '')) {
                alert('키워드를 입력해주세요!');
                return false;
            }
            if (!ps) { ps = new kakao.maps.services.Places(); }
            console.log("카카오받아옴");
            ps.keywordSearch(keyword, placesSearchCB);
        }

        function placesSearchCB(datas, status) {
            if (status === kakao.maps.services.Status.OK) {
                const addressNameSet = new Set();
                datas.forEach((data) => {
                    let addressName = data.address_name;
                    const addressNames = addressName.split(" ");
                    const lastPart = addressNames[addressNames.length - 1];
                    const addressRegex = /^[0-9-]+$/;
                    if (addressRegex.test(lastPart)) {
                        addressName = addressNames.slice(0, -1).join(" ");
                    }
                    addressNameSet.add(addressName);
                });
                let html = '';
                addressNameSet.forEach((addressName) => {
                    html += '<button type="button" class="tweet-modal__location-item">' +
                        '<span class="tweet-modal__location-item-label">' + addressName + '</span>' +
                        '<span class="tweet-modal__location-item-check"></span>' +
                        '</button>';
                });
                locationList.innerHTML = html;
            } else if (status === kakao.maps.services.Status.ZERO_RESULT) {
                alert('검색 결과가 존재하지 않습니다.');
                return;
            } else if (status === kakao.maps.services.Status.ERROR) {
                alert('검색 결과 중 오류가 발생했습니다.');
                return;
            }
        }

        if (geoBtn && locationView) {
            geoBtn.addEventListener("click", (e) => {
                showSubView(locationView);
                if (locationSearchInput) { locationSearchInput.value = ''; }
                if (locationList) { locationList.innerHTML = ''; }
                updateLocationUI();
            });
        }

        if (locationSearchBtn) {
            locationSearchBtn.addEventListener("click", (e) => {
                searchPlaces();
            });
        }

        if (locationList) {
            locationList.addEventListener("click", (e) => {
                const item = e.target.closest(".tweet-modal__location-item");
                if (!item) { return; }
                const allItems = locationList.querySelectorAll(".tweet-modal__location-item");
                for (let i = 0; i < allItems.length; i++) { allItems[i].classList.remove("isSelected"); }
                item.classList.add("isSelected");
                selectedLocation = item.querySelector(".tweet-modal__location-item-label").textContent;
                updateLocationUI();
                backToCompose();
            });
        }

        if (locationDeleteBtn) {
            locationDeleteBtn.addEventListener("click", (e) => {
                selectedLocation = null;
                updateLocationUI();
                if (locationList) { const allItems = locationList.querySelectorAll(".tweet-modal__location-item"); for (let i = 0; i < allItems.length; i++) { allItems[i].classList.remove("isSelected"); } }
                backToCompose();
            });
        }

        if (locationCompleteBtn) {
            locationCompleteBtn.addEventListener("click", (e) => { backToCompose(); });
        }

        if (locationClose) { locationClose.addEventListener("click", (e) => { backToCompose(); }); }

        // 태그 서브뷰
        const tagClose = tagView ? tagView.querySelector(".tweet-modal__tag-close") : null;
        if (tagClose) { tagClose.addEventListener("click", (e) => { backToCompose(); }); }
        const tagComplete = tagView ? tagView.querySelector("[data-tag-complete]") : null;
        if (tagComplete) { tagComplete.addEventListener("click", (e) => { backToCompose(); }); }

        // 미디어
        const mediaBack = mediaView ? mediaView.querySelector(".tweet-modal__media-header-btn--ghost") : null;
        if (mediaBack) { mediaBack.addEventListener("click", (e) => { backToCompose(); }); }
        const mediaSave = mediaView ? mediaView.querySelector("[data-media-save]") : null;
        if (mediaSave) { mediaSave.addEventListener("click", (e) => { backToCompose(); }); }

        // 판매글 선택
        const productBtn = overlay.querySelector(".tweet-modal__tool-btn--product");
        const productClose = productView ? productView.querySelector("[data-product-select-close]") : null;
        const productComplete = productView ? productView.querySelector("[data-product-select-complete]") : null;
        const productList = productView ? productView.querySelector("[data-product-select-list]") : null;
        const productEmpty = productView ? productView.querySelector("[data-product-empty]") : null;
        let selectedProduct = null;
        let cachedProducts = [];

        function renderProductList(products) {
            cachedProducts = products || [];
            if (!productList) { return; }
            if (!products || products.length === 0) { productList.innerHTML = ""; if (productEmpty) { productEmpty.classList.remove("off"); } return; }
            if (productEmpty) { productEmpty.classList.add("off"); }
            let html = "";
            for (let i = 0; i < products.length; i++) {
                const p = products[i];
                const img = (p.postFiles && p.postFiles.length > 0) ? p.postFiles[0] : "";
                const tags = (p.hashtags && p.hashtags.length > 0) ? p.hashtags.map(t => "#" + t.tagName).join(" ") : "";
                html += '<button type="button" class="draft-panel__item draft-panel__item--selectable" data-product-id="' + p.id + '">' +
                    '<span class="draft-panel__checkbox"><svg viewBox="0 0 24 24" aria-hidden="true"><g><path d="M9 20c-.264 0-.518-.104-.707-.293l-4.785-4.785 1.414-1.414L9 17.586 19.072 7.5l1.42 1.416L9.708 19.7c-.188.19-.442.3-.708.3z"></path></g></svg></span>' +
                    (img ? '<img class="draft-panel__avatar" src="' + img + '" />' : '') +
                    '<span class="draft-panel__item-body">' +
                    '<span class="draft-panel__text">' + (p.postTitle || "") + '</span>' +
                    '<span class="draft-panel__meta">' + tags + '</span>' +
                    '<span class="draft-panel__date">₩' + (p.productPrice || 0).toLocaleString() + ' · ' + (p.productStock || 0) + '개</span>' +
                    '</span></button>';
            }
            productList.innerHTML = html;
        }

        function renderSelectedProduct() {
            const existing = overlay.querySelector("[data-selected-product]");
            if (existing) { existing.remove(); }
            if (!selectedProduct) { return; }
            const editorWrap = overlay.querySelector(".tweet-modal__input-wrap");
            if (!editorWrap) { return; }
            const card = document.createElement("div");
            card.setAttribute("data-selected-product", "");
            card.className = "tweet-modal__selected-product";
            card.innerHTML = '<div class="selected-product__card">' +
                (selectedProduct.image ? '<img class="selected-product__image" src="' + selectedProduct.image + '" />' : '') +
                '<div class="selected-product__info"><strong class="selected-product__name">' + selectedProduct.name + '</strong><span class="selected-product__price">' + selectedProduct.price + '</span></div>' +
                '<button type="button" class="selected-product__remove"><svg viewBox="0 0 24 24" aria-hidden="true"><g><path d="M10.59 12L4.54 5.96l1.42-1.42L12 10.59l6.04-6.05 1.42 1.42L13.41 12l6.05 6.04-1.42 1.42L12 13.41l-6.04 6.05-1.42-1.42L10.59 12z"></path></g></svg></button></div>';
            card.querySelector(".selected-product__remove").addEventListener("click", (e) => {
                selectedProduct = null;
                card.remove();
                if (productBtn) { productBtn.disabled = false; }
                if (tagInput) {
                    const fromProductTags = tagInput.querySelectorAll('.tagDiv[data-from-product="true"]');
                    for (let i = 0; i < fromProductTags.length; i++) { fromProductTags[i].remove(); }
                    syncTagUI();
                }
            });
            editorWrap.appendChild(card);
        }

        if (productBtn && productView) {
            productBtn.addEventListener("click", async (e) => {
                const products = await _services.getMyProducts(getMemberId());
                renderProductList(products);
                showSubView(productView);
            });
        }
        if (productClose) { productClose.addEventListener("click", (e) => { backToCompose(); }); }
        if (productComplete) {
            productComplete.addEventListener("click", (e) => {
                const checkedItem = productList ? productList.querySelector(".draft-panel__item--selected") : null;
                if (checkedItem) {
                    const productId = checkedItem.getAttribute("data-product-id");
                    const product = cachedProducts.find(p => String(p.id) === String(productId));
                    const productTagCount = product && product.hashtags ? product.hashtags.length : 0;

                    // 합산 5개 초과 검증
                    if (getTagDivs().length + productTagCount > 5) {
                        alert("게시글 태그와 상품 태그를 합쳐 최대 5개까지만 가능해요.\n게시글 태그를 줄이거나 다른 상품을 선택하세요.");
                        return;
                    }

                    selectedProduct = {
                        name: checkedItem.querySelector(".draft-panel__text").textContent,
                        price: checkedItem.querySelector(".draft-panel__date").textContent,
                        image: checkedItem.querySelector(".draft-panel__avatar") ? checkedItem.querySelector(".draft-panel__avatar").src : "",
                        id: productId
                    };
                    renderSelectedProduct();
                    if (productBtn) { productBtn.disabled = true; }

                    // 상품 태그를 게시글 태그 칩으로 자동 추가 (data-from-product 마킹)
                    if (product && product.hashtags) {
                        product.hashtags.forEach(h => addTag(h.tagName, true));
                    }
                }
                backToCompose();
            });
        }
        if (productList) {
            productList.addEventListener("click", (e) => {
                const item = e.target.closest(".draft-panel__item");
                if (!item) { return; }
                const wasSelected = item.classList.contains("draft-panel__item--selected");
                const allItems = productList.querySelectorAll(".draft-panel__item--selected");
                for (let i = 0; i < allItems.length; i++) { allItems[i].classList.remove("draft-panel__item--selected"); const cb = allItems[i].querySelector(".draft-panel__checkbox"); if (cb) { cb.classList.remove("draft-panel__checkbox--checked"); } }
                if (!wasSelected) { item.classList.add("draft-panel__item--selected"); const cb = item.querySelector(".draft-panel__checkbox"); if (cb) { cb.classList.add("draft-panel__checkbox--checked"); } }
                if (productComplete) { productComplete.disabled = !productList.querySelector(".draft-panel__item--selected"); }
            });
        }

        // 볼드/이탤릭
        const boldBtn = overlay.querySelector(".tweet-modal__tool-btn--bold");
        const italicBtn = overlay.querySelector(".tweet-modal__tool-btn--italic");
        const editorEl = overlay.querySelector(".tweet-modal__editor");

        function syncFormatButtons() {
            if (boldBtn) { boldBtn.classList.toggle("active", document.queryCommandState("bold")); }
            if (italicBtn) { italicBtn.classList.toggle("active", document.queryCommandState("italic")); }
        }
        if (boldBtn && editorEl) { boldBtn.addEventListener("click", (e) => { editorEl.focus(); document.execCommand("bold"); syncFormatButtons(); }); }
        if (italicBtn && editorEl) { italicBtn.addEventListener("click", (e) => { editorEl.focus(); document.execCommand("italic"); syncFormatButtons(); }); }
        if (editorEl) { editorEl.addEventListener("keyup", (e) => { syncFormatButtons(); }); editorEl.addEventListener("mouseup", (e) => { syncFormatButtons(); }); }

        // 이모지 피커
        const emojiBtn = overlay.querySelector(".tweet-modal__tool-btn--emoji");
        const editor = overlay.querySelector(".tweet-modal__editor");
        let savedRange = null;

        if (editor) {
            editor.addEventListener("keyup", (e) => { const sel = window.getSelection(); if (sel.rangeCount > 0 && editor.contains(sel.anchorNode)) { savedRange = sel.getRangeAt(0).cloneRange(); } });
            editor.addEventListener("mouseup", (e) => { const sel = window.getSelection(); if (sel.rangeCount > 0 && editor.contains(sel.anchorNode)) { savedRange = sel.getRangeAt(0).cloneRange(); } });
            editor.addEventListener("input", (e) => { const sel = window.getSelection(); if (sel.rangeCount > 0 && editor.contains(sel.anchorNode)) { savedRange = sel.getRangeAt(0).cloneRange(); } });
        }

        function insertEmojiToEditor(emoji) {
            if (!editor) { return; }
            editor.focus();
            const sel = window.getSelection();
            if (savedRange && editor.contains(savedRange.startContainer)) { sel.removeAllRanges(); sel.addRange(savedRange); }
            const textNode = document.createTextNode(emoji);
            if (sel.rangeCount > 0 && editor.contains(sel.getRangeAt(0).startContainer)) {
                const range = sel.getRangeAt(0); range.deleteContents(); range.insertNode(textNode); range.setStartAfter(textNode); range.setEndAfter(textNode); sel.removeAllRanges(); sel.addRange(range);
            } else { editor.appendChild(textNode); const range = document.createRange(); range.setStartAfter(textNode); range.setEndAfter(textNode); sel.removeAllRanges(); sel.addRange(range); }
            savedRange = sel.getRangeAt(0).cloneRange();
            editor.dispatchEvent(new Event("input"));
        }

        if (emojiBtn && editor) {
            const picker = new EmojiButton({ position: "top-start", rootElement: overlay.querySelector(".tweet-modal") });
            picker.on("emoji", (emoji) => { insertEmojiToEditor(emoji); });
            emojiBtn.addEventListener("click", (e) => { picker.togglePicker(emojiBtn); });
        }

        // 파일 첨부
        const fileBtn = overlay.querySelector(".tweet-modal__tool-file .tweet-modal__tool-btn");
        const imageInput = overlay.querySelector(".tweet-modal__file-input");
        const attachmentPreview = overlay.querySelector("[data-attachment-preview]");
        const attachmentMedia = overlay.querySelector("[data-attachment-media]");
        let attachedFiles = [];
        let attachedUrls = [];

        if (fileBtn && imageInput) { fileBtn.addEventListener("click", (e) => { imageInput.click(); }); }

        function makeImageCell(index, url, cls) {
            return '<div class="media-cell ' + cls + '"><div class="media-cell-inner"><div class="media-img-container"><div class="media-bg" style="background-image:url(\'' + url + '\');"></div><img src="' + url + '" class="media-img" /></div><div class="media-btn-row"><button type="button" class="media-btn" data-edit-index="' + index + '"><span>수정</span></button></div><button type="button" class="media-btn-delete" data-remove-index="' + index + '"><svg viewBox="0 0 24 24" aria-hidden="true"><g><path d="M10.59 12L4.54 5.96l1.42-1.42L12 10.59l6.04-6.05 1.42 1.42L13.41 12l6.05 6.04-1.42 1.42L12 13.41l-6.04 6.05-1.42-1.42L10.59 12z"></path></g></svg></button></div></div>';
        }

        function renderImageGrid() {
            const n = attachedUrls.length;
            if (!attachmentMedia || n === 0) { return; }
            let html = "";
            if (n === 1) { html = '<div class="media-aspect-ratio media-aspect-ratio--single"></div><div class="media-absolute-layer">' + makeImageCell(0, attachedUrls[0], "media-cell--single") + '</div>'; }
            else if (n === 2) { html = '<div class="media-aspect-ratio"></div><div class="media-absolute-layer"><div class="media-row"><div class="media-col">' + makeImageCell(0, attachedUrls[0], "media-cell--left") + '</div><div class="media-col">' + makeImageCell(1, attachedUrls[1], "media-cell--right") + '</div></div></div>'; }
            else if (n === 3) { html = '<div class="media-aspect-ratio"></div><div class="media-absolute-layer"><div class="media-row"><div class="media-col">' + makeImageCell(0, attachedUrls[0], "media-cell--left-tall") + '</div><div class="media-col">' + makeImageCell(1, attachedUrls[1], "media-cell--right-top") + makeImageCell(2, attachedUrls[2], "media-cell--right-bottom") + '</div></div></div>'; }
            else { html = '<div class="media-aspect-ratio"></div><div class="media-absolute-layer"><div class="media-row"><div class="media-col">' + makeImageCell(0, attachedUrls[0], "media-cell--top-left") + makeImageCell(2, attachedUrls[2], "media-cell--bottom-left") + '</div><div class="media-col">' + makeImageCell(1, attachedUrls[1], "media-cell--top-right") + makeImageCell(3, attachedUrls[3], "media-cell--bottom-right") + '</div></div></div>'; }
            attachmentMedia.innerHTML = html;
        }

        function renderVideoAttachment() {
            if (!attachmentMedia || attachedFiles.length === 0) { return; }
            const file = attachedFiles[0]; const url = attachedUrls[0];
            attachmentMedia.innerHTML = '<div class="media-aspect-ratio media-aspect-ratio--single"></div><div class="media-absolute-layer"><div class="media-cell media-cell--single"><div class="media-cell-inner"><div class="media-img-container"><video class="tweet-modal__attachment-video" controls><source src="' + url + '" type="' + file.type + '"></video></div><div class="media-btn-row"><button type="button" class="media-btn" data-edit-index="0"><span>수정</span></button></div><button type="button" class="media-btn-delete" data-remove-index="0"><svg viewBox="0 0 24 24" aria-hidden="true"><g><path d="M10.59 12L4.54 5.96l1.42-1.42L12 10.59l6.04-6.05 1.42 1.42L13.41 12l6.05 6.04-1.42 1.42L12 13.41l-6.04 6.05-1.42-1.42L10.59 12z"></path></g></svg></button></div></div></div>';
        }

        function updateAttachmentView() {
            if (attachedFiles.length === 0) { attachmentPreview.classList.add("off"); attachmentMedia.innerHTML = ""; return; }
            attachmentPreview.classList.remove("off");
            if (attachedFiles[0].type.includes("video")) { renderVideoAttachment(); } else { renderImageGrid(); }
        }

        let editIndex = -1;
        function readFile(file, callback) { const reader = new FileReader(); reader.readAsDataURL(file); reader.addEventListener("load", (e) => { callback(e.target.result); }); }
        function readFilesSequential(fileList, startIdx, done) {
            if (startIdx >= fileList.length || attachedFiles.length >= 4) { done(); return; }
            const file = fileList[startIdx];
            if (file.type.includes("video")) { readFile(file, (path) => { attachedFiles = [file]; attachedUrls = [path]; done(); }); return; }
            if (attachedFiles.length > 0 && attachedFiles[0].type.includes("video")) { attachedFiles = []; attachedUrls = []; }
            readFile(file, (path) => { attachedFiles.push(file); attachedUrls.push(path); readFilesSequential(fileList, startIdx + 1, done); });
        }

        function resetModal() {
            const modalEditor = overlay.querySelector(".tweet-modal__editor");
            if (modalEditor) { modalEditor.innerHTML = ""; }
            backToCompose();
            attachedFiles = []; attachedUrls = [];
            if (attachmentPreview) { attachmentPreview.classList.add("off"); }
            if (attachmentMedia) { attachmentMedia.innerHTML = ""; }
            if (imageInput) { imageInput.value = ""; }
            editIndex = -1;
            if (tagInput) { const tags = tagInput.querySelectorAll(".tagDiv"); for (let i = 0; i < tags.length; i++) { tags[i].remove(); } tagInput.classList.add("off"); }
            isTagEditorOpen = false;
            if (tagEditor) { tagEditor.classList.add("off"); }
            if (tagToggle) { tagToggle.textContent = "태그 추가"; }
            if (tagField) { tagField.value = ""; }
            if (boldBtn) { boldBtn.classList.remove("active"); }
            if (italicBtn) { italicBtn.classList.remove("active"); }
            if (boardMenu) {
                boardMenu.classList.add("off");
                boardMenu.querySelectorAll(".boardMenuOption, .communityMenuItem")
                    .forEach(el => el.classList.remove("isSelected"));
                const generalOption = boardMenu.querySelector('[data-target="general"]');
                if (generalOption) generalOption.classList.add("isSelected");
            }
            if (audienceBtn) {
                audienceBtn.textContent = "일반";
                delete audienceBtn.dataset.communityId;
                audienceBtn.disabled = false;
            }
            if (catScroll && originalChipsHTML) { catScroll.innerHTML = originalChipsHTML; }
            selectedLocation = null;
            if (locationDisplay && locationDisplayText) { locationDisplayText.value = ""; locationDisplay.setAttribute("hidden", ""); }
            if (locationList) { const allItems = locationList.querySelectorAll(".tweet-modal__location-item"); for (let i = 0; i < allItems.length; i++) { allItems[i].classList.remove("isSelected"); } }
            selectedPostTempIndexes = [];
            if (postTempConfirmOverlay) { postTempConfirmOverlay.classList.add("off"); }
            updatePostTempFooter();
            selectedProduct = null;
            const existingProduct = overlay.querySelector("[data-selected-product]");
            if (existingProduct) { existingProduct.remove(); }
            if (productBtn) { productBtn.disabled = false; }
        }

        if (imageInput && attachmentPreview && attachmentMedia) {
            imageInput.addEventListener("change", (e) => {
                const files = e.target.files;
                if (files.length === 0) { return; }
                if (editIndex >= 0) {
                    const file = files[0];
                    readFile(file, (path) => {
                        if (path.includes("video")) { attachedFiles = [file]; attachedUrls = [path]; }
                        else { attachedFiles[editIndex] = file; attachedUrls[editIndex] = path; }
                        editIndex = -1; imageInput.value = ""; updateAttachmentView();
                    });
                    return;
                }
                readFilesSequential(files, 0, () => { imageInput.value = ""; updateAttachmentView(); });
            });

            attachmentMedia.addEventListener("click", (e) => {
                const removeBtn = e.target.closest("[data-remove-index]");
                if (removeBtn) { const idx = parseInt(removeBtn.getAttribute("data-remove-index")); attachedFiles.splice(idx, 1); attachedUrls.splice(idx, 1); updateAttachmentView(); return; }
                const editBtn = e.target.closest("[data-edit-index]");
                if (editBtn) { editIndex = parseInt(editBtn.getAttribute("data-edit-index")); imageInput.click(); }
            });
        }

        return {
            reset: resetModal,
            getAttachedFiles: () => attachedFiles,
            getTags: () => getTagDivs(),
            getSelectedProduct: () => selectedProduct,
            getSelectedLocation: () => selectedLocation,
            addTag: (tagName) => addTag(tagName),
            setLocation: (loc) => { selectedLocation = loc; updateLocationUI(); },
            setExistingFiles: (postFiles) => {
                attachedFiles = [];
                attachedUrls = postFiles.map(pf => pf.filePath);
                if (attachedUrls.length > 0) {
                    attachmentPreview.classList.remove("off");
                    const isVideo = postFiles[0].contentType === "video";
                    if (isVideo) {
                        attachmentMedia.innerHTML = '' +
                            '<div class="media-aspect-ratio media-aspect-ratio--single"></div>' +
                            '<div class="media-absolute-layer">' +
                                '<div class="media-cell media-cell--single">' +
                                    '<div class="media-cell-inner">' +
                                        '<div class="media-img-container">' +
                                            '<video class="tweet-modal__attachment-video" controls><source src="' + attachedUrls[0] + '"></video>' +
                                        '</div><button type="button" class="media-btn-delete" data-remove-index="0"><svg viewBox="0 0 24 24" aria-hidden="true"><g><path d="M10.59 12L4.54 5.96l1.42-1.42L12 10.59l6.04-6.05 1.42 1.42L13.41 12l6.05 6.04-1.42 1.42L12 13.41l-6.04 6.05-1.42-1.42L10.59 12z"></path></g></svg></button></div></div></div>';
                    } else {
                        renderImageGrid();
                    }
                }
            }
        };
    }

    // 작성 모달 핸들러: createPostButton / 닫기 / 글자수 게이지 / 제출 / 수정 진입.
    let _composeHandle = null;

    function setupCompose(options) {
        const opts = options || {};
        const overlay = opts.overlay;
        const mention = opts.mention;
        const ctx = opts.ctx;
        const getMemberId = opts.getMemberId;
        const onSubmitSuccess = opts.onSubmitSuccess;

        const closeBtn = overlay.querySelector(".tweet-modal__close");
        const editor = overlay.querySelector(".tweet-modal__editor");
        const gaugeText = overlay.querySelector(".composerGaugeText");
        const aiBtn = document.querySelector(".tweet-modal__ai");
        const submit = overlay.querySelector(".tweet-modal__submit");
        const maxLength = 500;
        let editPostId = null;

        // 사이드바 게시하기 버튼이 없는 페이지에서도 안전하도록 가드.
        const createPostButton = document.getElementById("createPostButton");
        if (createPostButton) {
            createPostButton.addEventListener("click", (e) => {
                overlay.classList.remove("off");
                editor.focus();
                const cs = overlay.querySelector(".category-scroll");
                if (cs) { requestAnimationFrame(() => { cs.dispatchEvent(new Event("scroll")); }); }
                // community-detailed 페이지면 audienceBtn 자동 선택 (현재 커뮤니티)
                const ctxEl = document.querySelector(".communityDetailPage[data-community-id]");
                const audienceBtn = overlay.querySelector(".audienceButton");
                if (ctxEl && audienceBtn) {
                    audienceBtn.dataset.communityId = ctxEl.dataset.communityId;
                    audienceBtn.textContent = ctxEl.dataset.communityName || "현재 커뮤니티";
                }
            });
        }

        async function openEdit(postId) {
            const post = await _services.getPost(postId, getMemberId());
            editPostId = postId;
            overlay.classList.remove("off");
            editor.textContent = post.postContent || "";
            editor.dispatchEvent(new Event("input"));
            submit.textContent = "수정";

            if (post.hashtags && post.hashtags.length > 0) {
                post.hashtags.forEach(h => ctx.addTag(h.tagName));
            }
            if (post.location) {
                ctx.setLocation(post.location);
            }
            if (post.postFiles && post.postFiles.length > 0) {
                ctx.setExistingFiles(post.postFiles);
            }

            // 편집 모드 — 기존 게시글의 커뮤니티 컨텍스트 표시 + audienceButton 비활성화
            const audienceBtn = overlay.querySelector(".audienceButton");
            if (audienceBtn) {
                if (post.communityId) {
                    audienceBtn.dataset.communityId = post.communityId;
                    audienceBtn.textContent = post.communityName || "현재 커뮤니티";
                } else {
                    delete audienceBtn.dataset.communityId;
                    audienceBtn.textContent = "일반";
                }
                audienceBtn.disabled = true;
            }

            editor.focus();
        }

        function close() {
            overlay.classList.add("off");
            editor.innerHTML = "";
            gaugeText.textContent = maxLength;
            gaugeText.style.color = "";
            submit.disabled = true;
            editPostId = null;
            submit.textContent = "게시";
            if (mention) { mention.closeMentionDropdown(); }
            if (ctx && ctx.reset) { ctx.reset(); }
        }

        closeBtn.addEventListener("click", () => { close(); });

        overlay.addEventListener("click", (e) => {
            if (e.target === overlay) { close(); }
        });

        editor.addEventListener("input", () => {
            const length = editor.textContent.length;
            const remaining = maxLength - length;
            gaugeText.textContent = remaining;
            if (remaining < 0) {
                gaugeText.style.color = "rgb(244, 33, 46)";
                submit.disabled = true;
            } else if (remaining < 20) {
                gaugeText.style.color = "rgb(255, 173, 31)";
                submit.disabled = false;
            } else {
                gaugeText.style.color = "";
                submit.disabled = length === 0;
            }
        });

        aiBtn.addEventListener("click", async () => {
            const content = editor.textContent;
            if (!content) {
                alert("내용을 입력해주세요.");
                return;
            }

            aiBtn.disabled = true;
            aiBtn.textContent = "분석 중...";

            try {
                const result = await postModalService.calcTrustScore(content);
                // -----------------------------------------------

                // overlay 기준으로 현재 상태 수집
                const postData = _trust.collectPostData(overlay, result);

                // 신뢰도 모달 열기
                _trust.openModal(postData);

            } catch (e) {
                console.error("[TrustModal] 분석 실패:", e);
                alert("신뢰도 분석에 실패했습니다. 다시 시도해 주세요.");
            } finally {
                aiBtn.disabled = false;
                aiBtn.textContent = "신뢰도 측정";
            }
        });

        submit.addEventListener("click", async () => {
            if (editor.textContent.length === 0) { return; }

            const formData = new FormData();
            formData.append("memberId", getMemberId());
            formData.append("postContent", editor.textContent);

            const files = ctx.getAttachedFiles();
            if (files.length > 0) {
                files.forEach(f => formData.append("files", f));
            }

            const tags = ctx.getTags();
            tags.forEach((tag, i) => {
                formData.append(`hashtags[${i}].tagName`, tag.textContent.replace("#", ""));
            });

            const location = ctx.getSelectedLocation();
            if (location) {
                formData.append("location", location);
            }

            const attachedProduct = ctx.getSelectedProduct();
            if (attachedProduct) {
                formData.append("productId", attachedProduct.id);
            }

            const mentionHandles = collectMentionHandles(editor);
            mentionHandles.forEach((h, i) => {
                formData.append(`mentionedHandles[${i}]`, h);
            });

            const audienceBtn = overlay.querySelector(".audienceButton");
            const communityId = audienceBtn?.dataset.communityId || null;
            const communityName = communityId ? audienceBtn.textContent.trim() : null;

            if (editPostId) {
                await _services.updatePost(editPostId, formData);
            } else if (communityId) {
                await postModalService.writeCommunityPost(communityId, formData);
            } else {
                await _services.writePost(formData);
            }

            const wasEditing = !!editPostId;

            close();
            if (wasEditing) {
                postModalService.showToast("수정되었습니다");
            } else if (communityName) {
                postModalService.showToast(`${communityName}에 게시되었습니다`);
            } else {
                postModalService.showToast("게시되었습니다");
            }
            if (onSubmitSuccess) { onSubmitSuccess({ communityId, communityName }); }
        });

        _composeHandle = { close: close, openEdit: openEdit };
        return _composeHandle;
    }

    // 외부 호출 진입점 — setupCompose 후에 사용 가능.
    function open() {
        const btn = document.getElementById("createPostButton");
        if (btn) { btn.click(); }
    }
    function openEdit(postId) {
        if (_composeHandle) { return _composeHandle.openEdit(postId); }
    }
    function close() {
        if (_composeHandle) { _composeHandle.close(); }
    }

    // 답글 모달 핸들러: 답글 버튼 클릭 시 원글 정보 세팅 + 모달 열기, 닫기, 글자수 게이지, 제출.
    function setupReply(options) {
        const opts = options || {};
        const overlay = opts.overlay;
        const mention = opts.mention;
        const ctx = opts.ctx;
        const getMemberId = opts.getMemberId;
        const onSubmitSuccess = opts.onSubmitSuccess;

        const closeBtn = overlay.querySelector(".tweet-modal__close");
        const editor = overlay.querySelector(".tweet-modal__editor");
        const gaugeText = overlay.querySelector(".composerGaugeText");
        const submit = overlay.querySelector(".tweet-modal__submit");
        const maxLength = 500;
        let targetPostId = null;
        // onReplySubmitSuccess 콜백에서 카운트 갱신 등을 처리할 수 있도록 활성 트리거 버튼을 추적한다.
        let activeReplyBtn = null;

        // 피드 카드의 답글 버튼 위임 — 동적 카드도 같은 경로로 모달이 열린다.
        document.addEventListener("click", (e) => {
            const replyBtn = e.target.closest(".tweet-action-btn[data-action='reply']");
            if (!replyBtn) { return; }
            const card = replyBtn.closest(".postCard");
            targetPostId = card ? card.dataset.postId : null;
            activeReplyBtn = replyBtn;

            if (card) {
                const sourceName = card.querySelector(".postName")?.textContent || "";
                const sourceHandle = card.querySelector(".postHandle")?.textContent || "";
                const sourceTime = card.querySelector(".postTime")?.textContent || "";
                const sourceText = card.querySelector(".postText")?.textContent || "";
                const sourceAvatarImg = card.querySelector(".postAvatarImage");
                const sourceInitial = card.querySelector(".postAvatar")?.textContent?.trim() || "?";

                document.getElementById("replyContextButton").textContent = sourceName + " @" + sourceHandle + " 님에게 보내는 답글";
                document.getElementById("replySourceName").textContent = sourceName;
                document.getElementById("replySourceHandle").textContent = sourceHandle;
                document.getElementById("replySourceTime").textContent = sourceTime;
                document.getElementById("replySourceText").textContent = sourceText;

                const sourceAvatarEl = document.getElementById("replySourceAvatar");
                if (sourceAvatarEl) {
                    sourceAvatarEl.innerHTML = sourceAvatarImg
                        ? `<img src="${sourceAvatarImg.src}" alt="" />`
                        : `<img src="${_layout.buildAvatarDataUri(sourceInitial)}" alt="" />`;
                }
            }

            overlay.classList.remove("off");
            editor.focus();
        });

        function close() {
            overlay.classList.add("off");
            editor.innerHTML = "";
            gaugeText.textContent = maxLength;
            gaugeText.style.color = "";
            submit.disabled = true;
            targetPostId = null;
            if (mention) { mention.closeMentionDropdown(); }
            if (ctx && ctx.reset) { ctx.reset(); }

            _trust.closeModal();
        }

        closeBtn.addEventListener("click", () => { close(); });

        overlay.addEventListener("click", (e) => {
            if (e.target === overlay) { close(); }
        });

        editor.addEventListener("input", () => {
            const length = editor.textContent.length;
            const remaining = maxLength - length;
            gaugeText.textContent = remaining;
            if (remaining < 0) {
                gaugeText.style.color = "rgb(244, 33, 46)";
                submit.disabled = true;
            } else if (remaining < 20) {
                gaugeText.style.color = "rgb(255, 173, 31)";
                submit.disabled = false;
            } else {
                gaugeText.style.color = "";
                submit.disabled = length === 0;
            }
        });

        submit.addEventListener("click", async () => {
            if (editor.textContent.length === 0) { return; }
            if (targetPostId) {
                const formData = new FormData();
                formData.append("memberId", getMemberId());
                formData.append("postContent", editor.textContent);

                const files = ctx.getAttachedFiles();
                if (files.length > 0) {
                    files.forEach(f => formData.append("files", f));
                }

                const tags = ctx.getTags();
                tags.forEach((tag, i) => {
                    formData.append(`hashtags[${i}].tagName`, tag.textContent.replace("#", ""));
                });

                const location = ctx.getSelectedLocation();
                if (location) {
                    formData.append("location", location);
                }

                const attachedProduct = ctx.getSelectedProduct();
                if (attachedProduct) {
                    formData.append("productId", attachedProduct.id);
                }

                const mentionHandles = collectMentionHandles(editor);
                mentionHandles.forEach((h, i) => {
                    formData.append(`mentionedHandles[${i}]`, h);
                });

                await _services.writeReply(targetPostId, formData);
            }
            const submittedPostId = targetPostId;
            const submittedButton = activeReplyBtn;
            close();
            postModalService.showToast("답글이 게시되었습니다");
            if (onSubmitSuccess && submittedPostId) {
                onSubmitSuccess({ postId: submittedPostId, button: submittedButton });
            }
        });

        return { close: close };
    }

    const _trust = (() => {

        // ----- SVG 아이콘 -----
        const ICONS = {
            check: `<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/></svg>`,
            warn:  `<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>`,
            error: `<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>`,
            image: `<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/></svg>`,
            tag:   `<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M21.41 11.58l-9-9C12.05 2.22 11.55 2 11 2H4c-1.1 0-2 .9-2 2v7c0 .55.22 1.05.59 1.42l9 9c.36.36.86.58 1.41.58.55 0 1.05-.22 1.41-.59l7-7c.37-.36.59-.86.59-1.41 0-.55-.23-1.06-.59-1.42zM5.5 7C4.67 7 4 6.33 4 5.5S4.67 4 5.5 4 7 4.67 7 5.5 6.33 7 5.5 7z"/></svg>`,
            pin:   `<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>`,
            box:   `<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M20 6h-2.18c.07-.31.18-.62.18-.96C18 3.36 16.64 2 15.04 2c-.96 0-1.86.48-2.4 1.2l-.64.8-.64-.8C10.86 2.48 9.96 2 9 2 7.36 2 6 3.36 6 5.04c0 .34.11.65.18.96H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2z"/></svg>`,
            thumb: `<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M1 21h4V9H1v12zm22-11c0-1.1-.9-2-2-2h-6.31l.95-4.57.03-.32c0-.41-.17-.79-.44-1.06L14.17 1 7.59 7.59C7.22 7.95 7 8.45 7 9v10c0 1.1.9 2 2 2h9c.83 0 1.54-.5 1.84-1.22l3.02-7.05c.09-.23.14-.47.14-.73v-2z"/></svg>`,
        };

        // ----- 점수 계산 -----
        function calcScores(data) {
            const aiPts    = data.aiResult === 2 ? 60 : data.aiResult === 1 ? 30 : 0;
            const imgPts   = data.hasImage    ? 20 : 0;
            const tagPts   = data.hasTag      ? 10 : 0;
            const extraPts = (data.hasLocation ? 5 : 0) + (data.hasProduct ? 5 : 0);
            const total    = Math.min(100, aiPts + imgPts + tagPts + extraPts);
            return { aiPts, imgPts, tagPts, extraPts, total };
        }

        // ----- 현재 compose modal 상태 수집 -----
        // overlay  : [data-compose-modal] 최상위 div
        // aiScore  : service에서 받은 0 | 1 | 2
        function collectPostData(overlay, aiScore) {
            // [이미지] data-attachment-media 안에 img/video 존재 여부
            // → attachmentPreview(.tweet-modal__attachment)에 "off" 가 없으면 첨부 상태이지만,
            //   더 정확하게 실제 자식 요소로 판별한다.
            const attachmentMedia = overlay.querySelector("[data-attachment-media]");

            // [태그] .tag-input 안의 .tagDiv 칩 개수로 판별
            // → tagDiv : addTag() 함수가 <span class="tagDiv"> 로 생성해서 .tag-input 에 추가
            const tagInput = overlay.querySelector(".tag-input");

            // [위치] .tweet-modal__location-display 버튼의 hidden 속성 + input value
            // → 위치 미선택: hidden 속성 있음 / 선택: removeAttribute("hidden")
            const locationDisplay = overlay.querySelector(".tweet-modal__location-display");
            const locationInput   = locationDisplay
                ? locationDisplay.querySelector(".tweet-modal__location-display-text-inner")
                : null;

            // [상품] renderSelectedProduct()가 [data-selected-product] 속성의 div를 .tweet-modal__input-wrap 에 추가
            // → 상품 선택 완료 후 DOM에 존재, 제거 버튼 클릭 시 remove()

            return {
                aiResult: aiScore,
                hasImage:    attachmentMedia
                    ? attachmentMedia.querySelectorAll("img, video").length > 0
                    : false,
                hasTag:      tagInput
                    ? tagInput.querySelectorAll(".tagDiv").length > 0
                    : false,
                hasLocation: locationDisplay && !locationDisplay.hidden
                    ? (locationInput?.value?.trim() ?? "").length > 0
                    : false,
                hasProduct:  !!overlay.querySelector("[data-selected-product]"),
            };
        }

        // ----- 개선 제안 생성 -----
        function buildSuggestions(data) {
            const items = [];

            if (data.aiResult === 2) {
                items.push({ type: "ok",   icon: ICONS.check, title: "내용이 주제에 부합합니다",       desc: "게시글의 내용이 카테고리 주제와 잘 맞습니다. 현재 내용을 유지하세요." });
            } else if (data.aiResult === 1) {
                items.push({ type: "warn", icon: ICONS.warn,  title: "내용이 주제를 일부 벗어났습니다", desc: "일부 내용이 선택한 카테고리와 관련이 적습니다. 내용을 보완하거나 적합한 카테고리로 변경해 보세요." });
            } else {
                items.push({ type: "bad",  icon: ICONS.error, title: "내용이 주제와 크게 다릅니다",     desc: "게시글이 선택한 카테고리와 맞지 않습니다. 내용을 전면 수정하거나 올바른 카테고리를 선택해 주세요." });
            }

            if (!data.hasImage)    items.push({ type: "info", icon: ICONS.image, title: "이미지를 첨부하면 신뢰도가 높아집니다", desc: "관련 사진이나 자료 이미지를 추가하면 거래 상품을 명확하게 확인 할 수 있습니다." });
            if (!data.hasTag)      items.push({ type: "info", icon: ICONS.tag,   title: "태그를 등록해 주세요",                  desc: "관련 키워드 태그를 추가하면 검색에 용이해집니다." });
            if (!data.hasLocation) items.push({ type: "info", icon: ICONS.pin,   title: "위치를 활용 해보세요",       desc: "거래 또는 연관 위치를 태그하면 신뢰도와 검색 노출이 향상됩니다." });
            if (!data.hasProduct)  items.push({ type: "info", icon: ICONS.box,   title: "상품을 등록하세요",     desc: "관련 상품을 게시글에 연결하면 원하는 거래를 빨리 찾을 수 있습니다." });

            if (data.aiResult === 2 && data.hasImage && data.hasTag && data.hasLocation && data.hasProduct) {
                items.push({ type: "ok", icon: ICONS.thumb, title: "모든 항목이 완벽합니다", desc: "이미지·태그·위치·상품까지 모두 등록되어 최고 수준의 신뢰도를 갖췄습니다." });
            }

            return items;
        }

        // ----- 모달 렌더 -----
        let _countAnim = null;

        function render(data) {
            const sc = calcScores(data);
            const { total } = sc;

            let strokeColor, gradeClass, gradeLabel, gradeSvg, heroDesc;
            if (total >= 80) {
                strokeColor = "#00ba7c"; gradeClass = "good"; gradeLabel = "신뢰도 높음";
                gradeSvg  = `<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm-2 16l-4-4 1.41-1.41L10 14.17l6.59-6.59L18 9l-8 8z"/></svg>`;
                heroDesc  = "게시글의 신뢰도가 높습니다. 지금 바로 게시할 수 있습니다.";
            } else if (total >= 50) {
                strokeColor = "#f4a100"; gradeClass = "warn"; gradeLabel = "주의 필요";
                gradeSvg  = `<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>`;
                heroDesc  = "신뢰도가 보통 수준입니다. 아래 개선 제안을 참고해 보완할 수 있습니다.";
            } else {
                strokeColor = "#f4212e"; gradeClass = "bad";  gradeLabel = "검토 필요";
                gradeSvg  = `<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>`;
                heroDesc  = "신뢰도가 낮습니다. 내용을 수정하고 이미지·태그·위치를 추가해 주세요.";
            }

            const arc   = document.getElementById("trustRingArc");
            const numEl = document.getElementById("trustRingNum");
            arc.style.stroke           = strokeColor;
            arc.style.strokeDashoffset = 201 - (total / 100) * 201;
            numEl.style.color          = strokeColor;

            if (_countAnim) cancelAnimationFrame(_countAnim);
            let cur = 0;
            const step = () => {
                cur = Math.min(cur + Math.ceil((total - cur) / 6 + 1), total);
                numEl.textContent = cur;
                if (cur < total) _countAnim = requestAnimationFrame(step);
            };
            requestAnimationFrame(step);

            const pill = document.getElementById("trustGradePill");
            pill.className = "trust-grade-pill " + gradeClass;
            pill.innerHTML = gradeSvg + " " + gradeLabel;
            document.getElementById("trustHeroDesc").textContent = heroDesc;

            const setBar = (vId, bId, pts, max) => {
                document.getElementById(vId).textContent = pts;
                document.getElementById(bId).style.width = Math.round((pts / max) * 100) + "%";
            };
            setTimeout(() => {
                setBar("trustV1", "trustB1", sc.aiPts,    60);
                setBar("trustV2", "trustB2", sc.imgPts,   20);
                setBar("trustV3", "trustB3", sc.tagPts,   10);
                setBar("trustV4", "trustB4", sc.extraPts, 10);
            }, 80);

            document.getElementById("trustSuggestList").innerHTML = buildSuggestions(data).map(item =>
                `<div class="trust-suggest-item">
                    <div class="trust-suggest-icon ${item.type}">${item.icon}</div>
                    <div class="trust-suggest-text">
                        <div class="trust-suggest-title">${item.title}</div>
                        <div class="trust-suggest-desc">${item.desc}</div>
                    </div>
                </div>`
            ).join("");
        }

        // ----- 열기 / 닫기 -----
        function openModal(data) {
            const overlay    = document.getElementById('trustModalOverlay');
            const tweetModal = document.querySelector('[data-compose-modal] .tweet-modal');
            if (!overlay || !tweetModal) return;

            // compose modal 기준 오른쪽 + 12px 간격
            const rect = tweetModal.getBoundingClientRect();
            overlay.style.left = (rect.right + 12) + 'px';
            overlay.style.top  = rect.top + 'px';

            ['trustB1','trustB2','trustB3','trustB4'].forEach(id => {
                const el = document.getElementById(id);
                if (el) el.style.width = '0%';
            });

            overlay.classList.remove('off');
            overlay.classList.add('open');
            requestAnimationFrame(() => render(data));
        }

        function closeModal() {
            const overlay = document.getElementById('trustModalOverlay');
            overlay?.classList.remove('open');
            setTimeout(() => overlay?.classList.add('off'), 300);
        }

        // ----- trust modal 버튼 이벤트 바인딩 (bootstrap 시 1회 호출) -----
        function bindModalButtons(composeSubmitBtn) {
            document.getElementById("trustModalClose")?.addEventListener("click", closeModal);
            document.getElementById("trustModalCancel")?.addEventListener("click", closeModal);

            document.getElementById("trustModalOverlay")?.addEventListener("click", (e) => {
                if (e.target === e.currentTarget) closeModal();
            });

            // trust modal의 "게시하기" → compose modal의 원래 submit 버튼 클릭
            document.getElementById("trustModalSubmit")?.addEventListener("click", () => {
                closeModal();
                composeSubmitBtn?.click();
            });
        }

        return { collectPostData, openModal, closeModal, bindModalButtons };
    })();

    // 페이지 진입 시 한 번 호출하면 작성/답글 모달이 자동으로 셋업된다. 마크업 없는 페이지는 자동 skip.
    function bootstrap(options) {
        const opts = options || {};
        init(opts);
        const getMemberId = opts.getMemberId || (() => null);

        const composeOverlay = document.querySelector("[data-compose-modal]");
        if (composeOverlay) {
            const composeEditor = composeOverlay.querySelector(".tweet-modal__editor");
            const composeMention = setupMention(composeEditor, composeEditor.parentElement, getMemberId);
            const composeCtx = setupSubViews(composeOverlay, getMemberId);
            setupCompose({
                overlay: composeOverlay,
                mention: composeMention,
                ctx: composeCtx,
                getMemberId: getMemberId,
                onSubmitSuccess: opts.onSubmitSuccess,
            });
        }

        // 자체 답글 모달이 있는 페이지(bookmark/mypage/Notification 등)는 skipReply: true 로 공용 셋업을 건너뛴다.
        if (!opts.skipReply) {
            const replyOverlay = document.querySelector("[data-reply-modal]");
            if (replyOverlay) {
                const replyEditor = replyOverlay.querySelector(".tweet-modal__editor");
                const replyMention = setupMention(replyEditor, replyEditor.parentElement, getMemberId);
                const replyCtx = setupSubViews(replyOverlay, getMemberId);
                setupReply({
                    overlay: replyOverlay,
                    mention: replyMention,
                    ctx: replyCtx,
                    getMemberId: getMemberId,
                    onSubmitSuccess: opts.onReplySubmitSuccess,
                });
            }
        }
    }

    return {
        init: init,
        open: open,
        openEdit: openEdit,
        close: close,
        setupMention: setupMention,
        collectMentionHandles: collectMentionHandles,
        setupSubViews: setupSubViews,
        setupCompose: setupCompose,
        setupReply: setupReply,
        bootstrap: bootstrap,
    };
})();
