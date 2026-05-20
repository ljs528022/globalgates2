-- ============================================================
-- community.sql  —  무역 전문 커뮤니티 더미 데이터
--   - 커뮤니티 10개 + 커뮤니티 썸네일 10장
--   - 게시글 300개 (커뮤니티당 30개, 무한스크롤 2회 이상 분량)
--   - 절반(15개/커뮤니티)에 사진 첨부 — 게시글 사진 풀 35장
--   - 회원은 DB의 기존 tbl_member id 1~20 그대로 사용
--   - S3 키 컨벤션: 2026/05/20/community/{community_NN,post_NN}.jpg
-- 실행:
--   PGPASSWORD=1234 psql -U globalgates -d globalgates -h localhost \
--     -f /Users/yoonchan/Desktop/community.sql
-- 멱등 처리:
--   - 커뮤니티/멤버/파일: NOT EXISTS / ON CONFLICT 가드
--   - 게시글: "해당 커뮤니티 게시글이 0개일 때만" 시드 (재실행해도 중복 X)
-- ============================================================

BEGIN;

-- ============================================================
-- 0-pre) 작가 풀 — 현재 DB에 존재하는 active 회원을 동적으로 매핑
--   1순위: '%@globalgates.test' 시드 회원 (무역 도메인 닉네임)
--   2순위: 시드가 없는 환경에서는 일반 active 회원
--   환경별 회원 ID 차이를 흡수하기 위해 임시 테이블 사용.
-- ============================================================
DO $writers$
DECLARE has_seed boolean;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM tbl_member
        WHERE member_status = 'active'::member_status
          AND member_email LIKE '%@globalgates.test'
    ) INTO has_seed;

    IF has_seed THEN
        CREATE TEMPORARY TABLE _gg_writers ON COMMIT DROP AS
        SELECT row_number() OVER (ORDER BY id) AS pos, id
        FROM (
            SELECT id FROM tbl_member
            WHERE member_status = 'active'::member_status
              AND member_email LIKE '%@globalgates.test'
            ORDER BY id
            LIMIT 20
        ) t;
    ELSE
        CREATE TEMPORARY TABLE _gg_writers ON COMMIT DROP AS
        SELECT row_number() OVER (ORDER BY id) AS pos, id
        FROM (
            SELECT id FROM tbl_member
            WHERE member_status = 'active'::member_status
            ORDER BY id
            LIMIT 20
        ) t;
    END IF;

    IF (SELECT COUNT(*) FROM _gg_writers) = 0 THEN
        RAISE EXCEPTION 'no active members found — cannot seed communities';
    END IF;
END $writers$;

-- ============================================================
-- 0) 이전 시드 정리
--    재실행 가능하게 — 우리가 만든 10개 커뮤니티의 게시글/첨부/썸네일 파일 삭제.
--    커뮤니티 자체와 멤버 가입 정보는 보존(이름·creator·멤버 그대로 유지).
--    신규 환경이면 삭제할 게 없어 무영향.
-- ============================================================
DO $cleanup$
DECLARE
    target_cids bigint[];
    target_pids bigint[];
    target_fids bigint[];
BEGIN
    SELECT array_agg(id) INTO target_cids
    FROM tbl_community
    WHERE community_name IN (
        '글로벌 수출 포럼','수입 바이어 네트워크','해운물류 전문가 모임','FTA·관세 실무 스터디',
        '무역금융 인사이트','무역 IT·디지털 혁신','K-Food 수출 클럽','K-Beauty 글로벌',
        '자동차부품 글로벌 거래','친환경·에너지 무역');

    IF target_cids IS NULL THEN RETURN; END IF;

    SELECT array_agg(id) INTO target_pids
    FROM tbl_post WHERE community_id = ANY(target_cids);

    target_fids := '{}'::bigint[];
    IF target_pids IS NOT NULL THEN
        SELECT coalesce(array_agg(file_id), '{}'::bigint[]) INTO target_fids
        FROM tbl_post_file WHERE post_id = ANY(target_pids);
        DELETE FROM tbl_post_file WHERE post_id = ANY(target_pids);
    END IF;

    SELECT target_fids || coalesce(array_agg(id), '{}'::bigint[]) INTO target_fids
    FROM tbl_community_file WHERE community_id = ANY(target_cids);
    DELETE FROM tbl_community_file WHERE community_id = ANY(target_cids);

    IF target_pids IS NOT NULL THEN
        DELETE FROM tbl_post WHERE id = ANY(target_pids);
    END IF;

    IF array_length(target_fids, 1) IS NOT NULL THEN
        DELETE FROM tbl_file WHERE id = ANY(target_fids);
    END IF;
END $cleanup$;

-- ============================================================
-- 1) 커뮤니티 10개
-- ============================================================
INSERT INTO tbl_community (community_name, description, creator_id, community_status, category_id)
SELECT t.name, t.descr,
       (SELECT id FROM _gg_writers
        WHERE pos = ((t.creator_id - 1) % (SELECT COUNT(*) FROM _gg_writers))::int + 1),
       'active'::community_status, t.cat_id
FROM (VALUES
    ('글로벌 수출 포럼',
     '신규 시장 개척, 수출 단가 협상, 바이어 발굴부터 통관·결제까지 — 한국 수출 현장 종사자들이 실무 경험을 나누는 종합 포럼입니다.',
     1::bigint, 1::bigint),
    ('수입 바이어 네트워크',
     '해외 제품 수입·소싱, 병행수입, OEM 발주, 거래선 검증 노하우를 공유합니다. 신뢰할 수 있는 바이어/공급사 매칭 중심.',
     2::bigint, 2::bigint),
    ('해운물류 전문가 모임',
     'FCL/LCL, 컨테이너 운임, 포워딩 실무, 항만·항공·창고 운영까지 — 물류 종사자들의 깊이 있는 정보 교류 공간.',
     3::bigint, 3::bigint),
    ('FTA·관세 실무 스터디',
     'FTA 활용, HS코드 분류, 원산지 증명, 관세 환급·과세 분쟁 등 관세사·통관팀이 함께 공부하는 스터디 커뮤니티.',
     4::bigint, 4::bigint),
    ('무역금융 인사이트',
     'L/C·D/P·T/T 결제 실무, 무역보험, 환헤지, 외화 운용 등 무역금융 전반의 인사이트를 공유합니다.',
     5::bigint, 5::bigint),
    ('무역 IT·디지털 혁신',
     '무역 플랫폼, ERP/SCM 연동, 블록체인 B/L, AI 바이어 매칭 등 디지털로 무역을 혁신하는 케이스 스터디.',
     6::bigint, 6::bigint),
    ('K-Food 수출 클럽',
     '한국 식품의 해외 수출 — HACCP·HALAL·FDA 인증, 콜드체인, 글로벌 식품 박람회 출전 경험을 공유합니다.',
     7::bigint, 7::bigint),
    ('K-Beauty 글로벌',
     '한국 화장품 수출, 해외 인증(CPNP·MoCRA·SFDA 등), 채널별 GTM, 인플루언서 마케팅 사례 공유.',
     8::bigint, 8::bigint),
    ('자동차부품 글로벌 거래',
     '완성차 OEM·애프터마켓·전기차 부품 수출입, 품질 인증(IATF 16949 등), Tier 1/2 공급망 정보 교환.',
     9::bigint, 9::bigint),
    ('친환경·에너지 무역',
     '태양광·풍력 모듈, 배터리, 수소 등 친환경 에너지 품목의 수출입과 ESG·CBAM 대응을 논의합니다.',
     10::bigint, 12::bigint)
) AS t(name, descr, creator_id, cat_id)
WHERE NOT EXISTS (SELECT 1 FROM tbl_community c WHERE c.community_name = t.name);

-- ============================================================
-- 2) 커뮤니티 썸네일 (tbl_file + tbl_community_file)
-- ============================================================
DO $thumbs$
DECLARE
    cmap CONSTANT text[][] := ARRAY[
        ARRAY['글로벌 수출 포럼',            'community_01.jpg'],
        ARRAY['수입 바이어 네트워크',        'community_02.jpg'],
        ARRAY['해운물류 전문가 모임',        'community_03.jpg'],
        ARRAY['FTA·관세 실무 스터디',        'community_04.jpg'],
        ARRAY['무역금융 인사이트',           'community_05.jpg'],
        ARRAY['무역 IT·디지털 혁신',         'community_06.jpg'],
        ARRAY['K-Food 수출 클럽',            'community_07.jpg'],
        ARRAY['K-Beauty 글로벌',             'community_08.jpg'],
        ARRAY['자동차부품 글로벌 거래',      'community_09.jpg'],
        ARRAY['친환경·에너지 무역',          'community_10.jpg']
    ];
    cname text;
    fname text;
    s3key text;
    cid bigint;
    new_fid bigint;
BEGIN
    FOR i IN 1..array_length(cmap, 1) LOOP
        cname := cmap[i][1];
        fname := cmap[i][2];
        s3key := '2026/05/20/community/' || fname;

        SELECT id INTO cid FROM tbl_community WHERE community_name = cname;
        IF cid IS NULL THEN CONTINUE; END IF;

        IF EXISTS (SELECT 1 FROM tbl_community_file WHERE community_id = cid) THEN
            CONTINUE;
        END IF;

        INSERT INTO tbl_file (original_name, file_name, file_path, file_size, content_type)
        VALUES (fname, s3key, s3key, 250000, 'image'::file_content_type)
        RETURNING id INTO new_fid;

        INSERT INTO tbl_community_file (id, community_id) VALUES (new_fid, cid);
    END LOOP;
END $thumbs$;

-- ============================================================
-- 3) 커뮤니티 멤버 — creator + 회원 1~20 전원 가입
-- ============================================================
INSERT INTO tbl_community_member (community_id, member_id, member_role)
SELECT c.id, c.creator_id, 'admin'::community_member_role
FROM tbl_community c
WHERE c.community_name IN (
    '글로벌 수출 포럼','수입 바이어 네트워크','해운물류 전문가 모임','FTA·관세 실무 스터디',
    '무역금융 인사이트','무역 IT·디지털 혁신','K-Food 수출 클럽','K-Beauty 글로벌',
    '자동차부품 글로벌 거래','친환경·에너지 무역')
ON CONFLICT (community_id, member_id) DO NOTHING;

INSERT INTO tbl_community_member (community_id, member_id, member_role)
SELECT c.id, w.id, 'member'::community_member_role
FROM tbl_community c
CROSS JOIN _gg_writers w
WHERE c.community_name IN (
    '글로벌 수출 포럼','수입 바이어 네트워크','해운물류 전문가 모임','FTA·관세 실무 스터디',
    '무역금융 인사이트','무역 IT·디지털 혁신','K-Food 수출 클럽','K-Beauty 글로벌',
    '자동차부품 글로벌 거래','친환경·에너지 무역')
ON CONFLICT (community_id, member_id) DO NOTHING;

-- ============================================================
-- 4) 게시글 사진 풀 — post_26.jpg ~ post_60.jpg (총 35장)
--    참고: post_01~25.jpg 는 기존(member_post) 시드가 이미 점유 중이므로 26부터 시작
--    여러 게시글이 같은 사진을 재사용 (현실적인 더미 패턴)
-- ============================================================
INSERT INTO tbl_file (original_name, file_name, file_path, file_size, content_type)
SELECT
    'post_' || lpad(gs::text, 2, '0') || '.jpg',
    '2026/05/20/community/post_' || lpad(gs::text, 2, '0') || '.jpg',
    '2026/05/20/community/post_' || lpad(gs::text, 2, '0') || '.jpg',
    250000,
    'image'::file_content_type
FROM generate_series(26, 60) gs
WHERE NOT EXISTS (
    SELECT 1 FROM tbl_file
    WHERE file_path = '2026/05/20/community/post_' || lpad(gs::text, 2, '0') || '.jpg'
);

-- ============================================================
-- 5) 게시글 (커뮤니티당 30개, 절반 사진 첨부)
--    형식: gg_seed_posts(<community-name>, <values>)
--    VALUES: (writer_member_id, title, content, photo_idx_or_null, minutes_ago)
-- ============================================================

-- ------------------------------------------------------------
-- [5-1] 글로벌 수출 포럼
-- ------------------------------------------------------------
WITH src AS (
    SELECT row_number() OVER () AS rn, t.*
    FROM (VALUES
        (1::bigint,  '[공유] 2026 상반기 수출 성장률 톱5 — 반도체·자동차 외 의외의 강세 품목',
         '관세청 1~4월 수출통계 정리해봤습니다. 반도체(+34%)·자동차(+18%)는 예상대로지만, 화장품(+22%)·라면류(+27%)·전기차 충전기(+41%)가 두드러집니다. 내수 부진을 수출로 메우는 흐름이 뚜렷합니다. 각자 업계 체감은 어떠신가요?',
         31::int, 12*60+30),
        (2,  '[질문] 신규 시장 진출 전 가장 먼저 검증해야 할 3가지가 뭘까요',
         '동남아 진출 검토 중인데, 시장 규모·관세·인증 외에 실무자분들이 가장 먼저 확인하시는 항목이 궁금합니다. 우리는 결제 회수 가능성을 1번으로 두는데 다들 어떠신가요?',
         NULL, 18*60+5),
        (3,  '[경험] 인도네시아 첫 수출 — BPOM 인증 지연으로 통관 2주 묶임',
         '화장품 첫 컨테이너 보냈는데 BPOM 등록번호 라벨링 미스로 자카르타 항에서 2주 묶였습니다. 등록은 미리 했는데, 단상자 인쇄에 등록번호 누락. 인쇄 단계에서 체크리스트 필수입니다.',
         15, 22*60+10),
        (4,  '[정보] KOTRA 지사화 사업 D-7 — 자격과 작년 활용 후기',
         '5월 27일까지 신청 마감입니다. 매출 100억 이하 중소·중견 가능. 작년에 호치민 지사화 썼는데 현지 마케팅·바이어 발굴 비용 절반 정도 커버됐습니다. 신청 서류 준비 4~5일 봐야 합니다.',
         NULL, 30*60+0),
        (5,  '[의견] 수출바우처 vs 글로벌강소기업+ vs 월드클래스 — 어떤 단계에 무엇이?',
         '연 매출 30억대인데 수출바우처는 한도가 작고, 글로벌강소기업+는 진입장벽이 모호합니다. 비슷한 규모 분들 어떤 사업 활용 중이신가요?',
         NULL, 36*60+45),
        (6,  '[공유] 영문 인보이스 양식 — INCOTERMS 2020 반영 최신본',
         '회사 영문 인보이스 템플릿 INCOTERMS 2020·CBAM 코멘트 라인까지 반영해서 업데이트했습니다. 필요하신 분 댓글 남겨주시면 양식 정리해서 공유드립니다. (한·영 병기)',
         24, 44*60+20),
        (7,  '[경고] 위장 바이어 사례 — 가짜 LC 사본으로 샘플만 챙기고 잠적',
         '두바이 GMAIL 도메인 바이어 주의. LC 발행 은행이 실재하지 않는 곳이었고, 샘플 100세트 받은 뒤 연락 두절. 발행은행은 SWIFT BIC로 한 번 더 검증하세요.',
         NULL, 50*60+15),
        (8,  '[팁] 첫 해외 영업 채용 — 어학·문화·도메인 중 우선순위',
         '저희는 도메인 80%, 어학 15%, 문화 5% 비중으로 봅니다. 영어는 메일·자료로 보완 가능하지만 무역 도메인은 6개월 안에 안 채워집니다. 다들 어떻게 가중치 두시나요?',
         NULL, 56*60+40),
        (9,  '[질문] CIF 보험 가입은 어디서? 한국무역보험공사 vs 민간',
         'CIF 조건 첫 거래라 보험사 고민입니다. K-SURE 단기수출보험으로 충분한지, 아니면 메리츠·삼성화재 적하보험을 따로 가입하는 게 나은지 경험담 부탁드립니다.',
         23, 60*60+0),
        (10, '[정보] 부산항 신항 ODCY 야적 비용 6월부터 8% 인상',
         'BPA 공지 확인했습니다. 컨테이너 야적료 인상은 결국 화주 부담으로 전가됩니다. FCL 자주 보내시는 분들 6월 이후 견적 재산정 필요합니다.',
         1, 68*60+15),
        (11, '[경험] 알리바바닷컴 골드서플라이어 1년 운영 — 매출 추이 공유',
         '1~3월 문의 폭주, 실제 계약 전환율 4.2%. 비용 대비 ROI는 8개월차부터 양수. 제품 사진 퀄리티와 RFQ 응답 속도가 핵심입니다. 24시간 내 첫 응답 못 하면 거의 떨어집니다.',
         NULL, 75*60+30),
        (12, '[공유] 적하목록 B/L 작성 실수로 통관 거부된 5가지 케이스',
         '1) HS코드 자릿수 부족 2) Shipper 주소 영문 표기 오류 3) 마크 & 넘버 누락 4) Net/Gross 무게 역전 5) Description "Sample" 단독 표기. 사소해 보여도 통관 거부 사유.',
         12, 82*60+50),
        (13, '[질문] ISF 10+2 지연 시 페널티 어떻게 되나요',
         'CBP 페널티 최대 USD 5,000인데, 실제로 매번 부과하지는 않는다고 들었습니다. 작년 한 번 지각했는데 무경고였습니다. 다들 경험치는 어떠신가요?',
         NULL, 90*60+10),
        (14, '[의견] 환율 1,500원 시대, 수출 단가 재협상 어떻게 풀어가시나요',
         '바이어들도 인플레 부담이 커서 단가 인상 협상이 어렵습니다. 우리는 인상 대신 결제 조건(전금 비율 상향)으로 푸는 중인데, 다른 접근 있으면 공유 부탁드립니다.',
         22, 96*60+25),
        (15, '[경험] 폴란드 바이어 — 가격보다 납기 보장에 더 민감',
         '베를린 박람회에서 만난 폴란드 바이어, MOQ나 단가보다 "Lead Time + 지연 시 페널티 조항"을 먼저 물었습니다. 동유럽 진출 시 SLA 명문화가 핵심으로 보입니다.',
         29, 102*60+0),
        (16, '[공유] EU CBAM — 중소 수출기업 영향 정리',
         '직접 대상은 철강·알루미늄·시멘트·전력·비료·수소 6개 품목이지만, 우리처럼 부품 공급하는 회사도 바이어 요청으로 EE(임베디드 배출량) 보고 자료 요구받는 사례 늘었습니다.',
         32, 108*60+15),
        (17, '[팁] 영어 협상 — "가격 인하 거절" 톤 5문장',
         '"We understand the price sensitivity, however our margin is already optimized at this level." 깍지 않으면서 거절하는 톤. 더 좋은 표현 있으면 댓글 부탁드립니다.',
         NULL, 115*60+30),
        (18, '[질문] FOB vs FCA — INCOTERMS 2020 어떻게 구분하시나요',
         'FOB는 본선적재 시점, FCA는 운송인 인도 시점이 책임 이전인데, 컨테이너 화물에 FOB 쓰는 게 사실 부정확합니다. 그런데 바이어가 FOB로 고집할 때 어떻게 설득하시는지?',
         NULL, 122*60+45),
        (19, '[공유] 중남미 진출 — NCM(브라질 HS) 매핑 가이드',
         '한국 HS 10자리를 브라질 NCM 8자리로 매핑할 때, 끝 2자리 차이로 관세율이 8%p 벌어지는 경우가 많습니다. Receita Federal 사이트 NCM Buscador 활용 추천.',
         NULL, 130*60+0),
        (20, '[경험] 견적서 Validity 누락 — 환율 변동 손실 본 케이스',
         '6월 견적에 Validity 명시 안 했더니, 바이어가 11월에 그 가격으로 PO 띄움. 환율 6% 빠진 상태라 마진 거의 증발. 견적엔 항상 "Validity: 30 days from issue date" 필수.',
         25, 138*60+20),
        (21, '[정보] KOTRA 단체 해외전시회 일정 — 6~8월',
         '하반기 단체관 참가비 지원 일정: 6월 SIAL Toronto, 7월 HKTDC, 8월 China Beauty Expo. 신청 마감은 행사 2개월 전. KOTRA 해외전시포털 참고.',
         NULL, 145*60+30),
        (22, '[의견] 자사몰 vs B2B 마켓플레이스 — 첫 수출은 어디부터',
         '브랜드 인지도 낮은 초기엔 마켓플레이스(알리바바·아마존비즈니스) 트래픽이 압도적입니다. 자사몰은 어느 단계부터 의미 있을까요?',
         NULL, 152*60+0),
        (23, '[경고] T/T 100% 후불 — 절대 받지 말아야 할 결제 조건',
         '나이지리아·필리핀 일부 바이어가 자주 제안하는데, 회수 실패 사례가 너무 많습니다. 최소 30% 전금 + 70% 선적 후 즉시 T/T가 마지노선이라고 봅니다.',
         NULL, 160*60+15),
        (24, '[공유] 수출 신고필증 EL 번호 — 부가세 환급 절차',
         'EL 번호로 영세율 적용 받아 부가세 환급 가능. 신고서 확정일 기준 6개월 내 신청. 처음이라면 세무서 부가세과 사전 상담 한 번 추천드립니다.',
         NULL, 168*60+45),
        (25, '[질문] 결제 조건 D/P, D/A, L/C, T/T 비율 어떻게 분배하시나요',
         '저희는 신규 바이어 100% LC at sight, 1년 거래 후 50% LC + 50% T/T, 3년 이후 T/T 100% 정도로 운영합니다. 다른 회사 룰 궁금합니다.',
         23, 178*60+0),
        (26, '[경험] 첫 OEM 수출 — 바이어 한국 공장 실사에서 본 부분',
         '미국 바이어가 실사 와서 가장 꼼꼼히 본 곳은 1) QC 검사 동선 2) 원자재 입고~출고 추적 3) 직원 안전 장비. 가격은 둘째였습니다. 공장 환경이 곧 신뢰입니다.',
         3, 188*60+30),
        (27, '[팁] 영문 카탈로그 — 한국식 직역 피해야 할 5가지 표현',
         '"High quality" 같은 모호한 형용사는 빼고 구체 스펙으로. "Strong company" → "Founded in 2008, 12 years of OEM experience". 자기소개도 숫자가 핵심입니다.',
         NULL, 195*60+0),
        (28, '[정보] K-SURE 단기수출보험 한도 확대 발표',
         '중소·중견 한도 1.5배 확대(공시 5월 12일). 신용평가 등급 BB- 이상이면 추가 심사 없이 자동 적용. 단가 인상 대신 보험으로 회수 리스크 줄이는 전략 추천.',
         NULL, 205*60+15),
        (29, '[의견] 수출 첫걸음 단계 — 가장 큰 장벽은 무엇이라고 보시는지',
         '저는 "정보 비대칭"이 1번이라고 봅니다. 자금이나 인력은 어떻게든 채울 수 있는데, 어떤 박람회가 우리 제품에 맞는지조차 알기 어렵습니다. 다들 어떻게 극복하셨나요?',
         NULL, 215*60+30),
        (30, '[공유] 30년 차 수출 베테랑 인터뷰 — 신입에게 하고 싶은 말 3가지',
         '1) 첫 거래의 단가를 절대 깎지 마라(레퍼런스가 된다) 2) 바이어 사무실에 직접 가라(메일·전화론 모름) 3) 클레임은 무조건 24시간 안에 답하라. 단순하지만 안 지키면 매번 당합니다.',
         28, 225*60+0)
    ) AS t(member_id, title, content, photo_idx, minutes_ago)
),
ck AS (
    SELECT 1 AS go
    WHERE NOT EXISTS (
        SELECT 1 FROM tbl_post p
        JOIN tbl_community c ON c.id = p.community_id
        WHERE c.community_name = '글로벌 수출 포럼'
    )
),
ins AS (
    INSERT INTO tbl_post (member_id, community_id, post_status, title, content, created_datetime)
    SELECT (SELECT id FROM _gg_writers
            WHERE pos = ((src.member_id - 1) % (SELECT COUNT(*) FROM _gg_writers))::int + 1),
           (SELECT id FROM tbl_community WHERE community_name = '글로벌 수출 포럼'),
           'active'::post_status,
           src.title,
           src.content,
           now() - (src.minutes_ago * interval '1 minute')
    FROM src, ck
    RETURNING id, content
)
INSERT INTO tbl_post_file (post_id, file_id)
SELECT ins.id,
       (SELECT id FROM tbl_file
        WHERE file_path = '2026/05/20/community/post_' || lpad((src.photo_idx + 25)::text, 2, '0') || '.jpg')
FROM ins
JOIN src ON src.content = ins.content
WHERE src.photo_idx IS NOT NULL;

-- ------------------------------------------------------------
-- [5-2] 수입 바이어 네트워크
-- ------------------------------------------------------------
WITH src AS (
    SELECT row_number() OVER () AS rn, t.*
    FROM (VALUES
        (2::bigint,  '[질문] 중국 1688 vs 알리바바닷컴 — 소싱 시 어떻게 활용하시나요',
         '1688이 같은 공장 가격 30~50% 저렴한 건 알지만, MOQ·결제·언어 장벽이 큽니다. 한국 에이전트 끼고 1688 쓰시는 분들 수수료 비율과 만족도 궁금합니다.',
         NULL, 8*60+15),
        (4,  '[경험] 베트남 빈증성 가구 공장 실사 — 품질은 OK, 납기 리스크',
         '하노이에서 차로 1시간, 60명 규모 공장 다녀왔습니다. 마감 품질은 기대 이상인데, 우기(7~9월) 자재 입고 지연이 잦다고 합니다. 시즌 발주는 한 달 버퍼 필수.',
         3, 14*60+30),
        (5,  '[정보] 일본 후쿠오카 무역회 — 한국 바이어 모집 공고',
         '6월 18일 후쿠오카상공회의소 주최, 일본 중소제조사 매칭 행사. 한국에서 25개 사 모집. 식품·생활용품·뷰티 위주. 신청은 KITA 통해서.',
         NULL, 22*60+0),
        (7,  '[공유] 수입 거래선 검증 체크리스트 10항목',
         '1)사업자등록 원본 2)최소 3년 운영 이력 3)기존 수출 바이어 레퍼런스 2개 4)공장 사진+영상 5)ISO·BSCI 인증 6)Skype 영상 통화 7)D&B 리포트 8)은행 거래 잔액 증명 9)샘플 실측 검증 10)Trial Order 후 풀 발주.',
         24, 30*60+45),
        (8,  '[질문] 병행수입 — 정식 수입원과 분쟁 가능성 어디까지?',
         '소비자 입장에서 상표법은 문제 없는데, 정식 수입원이 A/S 거부하면서 컴플레인 폭주합니다. 다들 정식 수입원과 병존하는 카테고리 운영하시나요?',
         NULL, 38*60+10),
        (9,  '[경험] 튀르키예 카펫 — 환율 변동으로 단가 협상 까다로움',
         '리라화가 출렁이니까 USD로 견적 받아도 매번 재협상. "Quoted in USD, locked at current TRY rate" 같은 조항을 견적서에 명시하는 게 안정적입니다.',
         NULL, 46*60+25),
        (10, '[공유] 중국 광저우 캔톤페어 — 1차/2차/3차 기수별 품목 가이드',
         '1차(4월 중순/10월 중순): 전자·기계 / 2차: 일상생활용품·식품 / 3차: 의류·패션. 잘못 가면 한 주 통째로 허탕입니다. 처음 가시는 분 일정 꼭 확인.',
         NULL, 55*60+0),
        (11, '[정보] 인도 GST 인보이스 — e-Invoicing 의무화 단계',
         '연 매출 5억 루피 이상 회사는 IRN(Invoice Reference Number) 발급 필수. 한국 바이어가 인도 공급사로부터 받을 때, IRN 없는 인보이스는 추후 분쟁 시 효력 약합니다.',
         NULL, 63*60+30),
        (12, '[경고] 위챗·웨이보 광고 보고 접근하는 "특가" 수입 제안 주의',
         '광저우 도매시장 상호를 도용해 SNS로 한국 바이어에 접근하는 사기 패턴 증가. 정상 가격보다 40% 이상 싸면 거의 사기라고 보시면 됩니다. 송금 전 반드시 영상 통화로 공장 확인.',
         NULL, 72*60+15),
        (13, '[질문] FOB 상하이 vs FOB 닝보 — 어디가 더 안정적?',
         '닝보가 컨테이너 적체 덜한 편이라 리드타임 짧다고 들었는데, 내륙운송 비용이 상하이보다 비싸다는 의견도 있습니다. 실무 경험으로는 어떠신가요?',
         NULL, 81*60+45),
        (14, '[공유] 폴란드 바르샤바 식품 박람회 ProsweetsPL — 후기',
         '한국 과자류 부스 운영. 호밀빵 종주국답게 단맛에 보수적이지만, 알로에 음료·곤약 젤리에 반응 좋았습니다. EE 마크(유럽 식품인증) 없으면 명함도 안 받습니다.',
         14, 90*60+0),
        (15, '[경험] 인도네시아 자카르타 — 무슬림 시장 진출 시 할랄 인증 우선순위',
         'BPJPH(인도네시아 할랄청) 인증 없으면 대형 유통(인도마렛·알파마트) 진입 자체 불가. JAKIM(말련) 인증 있으면 BPJPH 호환 가능하지만, 별도 등록 필요.',
         NULL, 100*60+30),
        (16, '[팁] 베트남 송금 — Banking 일정과 USD 보유 한도',
         '베트남 동화(VND) 약세로 현지 공급사 USD 결제 선호. 단, 베트남 은행 USD 출금 한도(법인 월 50만 USD)에 걸리는 경우 있어 분할 결제 사전 합의 필수.',
         NULL, 110*60+0),
        (17, '[정보] 멕시코 — IMMEX 프로그램 활용한 임가공 수입 절세',
         '멕시코 IMMEX(임가공 면세 프로그램) 활용 시 부품 수입 관세·VAT 면제. 한국 본사 → 멕시코 자회사 → 미국 수출 구조 짤 때 핵심.',
         NULL, 120*60+15),
        (18, '[질문] 수입 통관 — 자체 통관 vs 관세사 위탁 비용 손익분기',
         '월 컨테이너 5개 미만이면 관세사 위탁이 압도적으로 효율적이라는 게 일반론인데, 자체 통관팀 두신 분들 인력 구성과 비용 구조 공유 부탁드립니다.',
         NULL, 130*60+0),
        (19, '[공유] 우즈베키스탄 면화·섬유 소싱 — 가성비 좋은데 정보 부족',
         '중앙아 면화 품질 매우 좋고 가격 경쟁력 있습니다. 다만 영문 자료 거의 없고 러시아어·우즈벡어 위주. UZBEKLIGHTINDUSTRY 협회 통하면 매칭 가능.',
         NULL, 142*60+30),
        (20, '[경험] 광저우 도매시장 — 직접 방문 vs 한국 에이전트 활용',
         '저는 첫 1년은 무조건 직접 갑니다. 시장 동선·가격 협상·공장 매핑이 머리에 박혀야 그 다음 에이전트 활용해도 휘둘리지 않습니다.',
         8, 152*60+0),
        (1,  '[의견] 알리바바 신뢰등급 — Verified Supplier가 정말 의미 있나',
         '돈만 내면 받는 인증이라는 의견도 있는데, 실제로는 사업자등록 검증·공장 실사 사진까지 등록되어 있어 무Verified보다는 신뢰도 차이 큽니다. 다들 어떻게 보시나요?',
         NULL, 162*60+45),
        (3,  '[정보] 태국 BOI — 외국인 투자 인센티브 업데이트',
         'BOI 그룹A1(첨단 R&D) 법인세 8년 면제. 한국 부품·자동차 회사 베트남 다음 진출지로 태국 주목 중. 한-태 협력 강한 분야는 자동차·전자·식품.',
         NULL, 175*60+0),
        (6,  '[경고] 인도 첫 거래 — Advance Payment 30%가 회수 불가 사례',
         '뭄바이 공급사에 30% 전금 보냈는데, 환경 인허가 지연으로 출고 4개월 지연. 결국 계약 해지했지만 전금 회수 6개월째 진행 중. 인도 첫 거래는 LC at sight 추천.',
         NULL, 188*60+30),
        (10, '[공유] 한국 화학물질관리법(K-REACH) — 수입자 의무',
         '연 1톤 이상 화학물질 수입자는 등록 의무. 신규 물질은 검출 농도 0.1% 이상이면 별도 신고. 향수·세제·코팅제 등 의외로 K-REACH 걸리는 품목 많습니다.',
         NULL, 200*60+15),
        (11, '[질문] 수입 의류 KC 인증 — 어린이 제품 기준',
         '어린이용 의류는 36개월 미만 KC 어린이 안전인증 필수. 모르고 들여왔다가 통관 후 자진회수한 사례 있습니다. 13세 이하 어린이 제품 기준도 다르니 확인 필수.',
         NULL, 212*60+30),
        (12, '[경험] 두바이 자유무역지대 JAFZA — 중동·아프리카 허브',
         'JAFZA 법인 설립 후 중동·아프리카 재수출 베이스로 활용. 100% 외국인 지분 가능, 법인세 0%(2023년 이후 9%). 단, 현지 시장 진입은 별도 라이선스 필요.',
         33, 224*60+0),
        (13, '[팁] 중국 공장 — 음력 1월(춘절) 전 발주 마감 일정',
         '춘절은 매년 1월 말~2월 중순. 12월 중순까지 발주 안 하면 2월 말까지 생산 정체. 매년 반복되는 이슈인데도 매번 못 챙기는 회사 많습니다.',
         NULL, 235*60+45),
        (15, '[공유] 페루 — 한-페루 FTA 활용한 수입 관세 인하 품목',
         '한-페루 FTA 11년차. 농산물·수산물·섬유 일부 품목 관세 0%. 페루산 망고·블루베리 수입 검토 시 원산지 증명서(POR-PE) 챙기면 효과 큼.',
         NULL, 248*60+30),
        (16, '[정보] 일본 — 식품 위생법 개정으로 HACCP 의무화 영향',
         '일본 모든 식품 사업자 HACCP 의무 적용 5년차. 한국 → 일본 식품 수출 시 일본 수입자가 HACCP 준수 증빙을 요구하는 사례 늘었습니다.',
         NULL, 260*60+0),
        (17, '[질문] 중국 광동·강소 — 동일 품목 가격 차이 어디서 오나',
         '광동은 글로벌 노출 많아 단가가 강소보다 10~15% 비쌉니다. 강소는 내수 비중 높아 영어 응대 약한 곳 많은 게 trade-off. 다들 어떻게 균형 잡으시나요?',
         NULL, 272*60+30),
        (18, '[경험] 이탈리아 가죽 — 진짜 풀그레인 vs 보세가죽 구분법',
         '풀그레인은 모공·결이 자연스러운 흔적이 남고, 보세가죽은 코팅막이 매끈합니다. 단면을 면도칼로 살짝 잘라보면 가장 확실. 첫 수입 시 샘플 단면 사진 요구하세요.',
         NULL, 285*60+15),
        (19, '[공유] 베트남 호치민 항만 — 카이멥-티바이 vs 사이공항',
         '대형선은 카이멥-티바이(딥워터), 소형·국내 환적은 사이공항. 호치민 시내 접근성은 사이공 우위지만, 4,000TEU 이상 모선은 카이멥 필수.',
         NULL, 298*60+0),
        (20, '[의견] 첫 수입 — Trial Order는 얼마부터가 적당한가',
         '저희는 USD 5,000~8,000 사이에서 Trial Order 1회 → 만족 시 본 발주. 너무 작으면 공급사가 성의 없게 처리, 너무 크면 우리가 손실 위험. 이 구간이 골든 사이즈로 보입니다.',
         NULL, 310*60+0)
    ) AS t(member_id, title, content, photo_idx, minutes_ago)
),
ck AS (
    SELECT 1 AS go
    WHERE NOT EXISTS (
        SELECT 1 FROM tbl_post p
        JOIN tbl_community c ON c.id = p.community_id
        WHERE c.community_name = '수입 바이어 네트워크'
    )
),
ins AS (
    INSERT INTO tbl_post (member_id, community_id, post_status, title, content, created_datetime)
    SELECT (SELECT id FROM _gg_writers
            WHERE pos = ((src.member_id - 1) % (SELECT COUNT(*) FROM _gg_writers))::int + 1),
           (SELECT id FROM tbl_community WHERE community_name = '수입 바이어 네트워크'),
           'active'::post_status,
           src.title,
           src.content,
           now() - (src.minutes_ago * interval '1 minute')
    FROM src, ck
    RETURNING id, content
)
INSERT INTO tbl_post_file (post_id, file_id)
SELECT ins.id,
       (SELECT id FROM tbl_file
        WHERE file_path = '2026/05/20/community/post_' || lpad((src.photo_idx + 25)::text, 2, '0') || '.jpg')
FROM ins
JOIN src ON src.content = ins.content
WHERE src.photo_idx IS NOT NULL;

-- ------------------------------------------------------------
-- [5-3] 해운물류 전문가 모임
-- ------------------------------------------------------------
WITH src AS (
    SELECT row_number() OVER () AS rn, t.*
    FROM (VALUES
        (3::bigint, '[정보] 5월 3주차 SCFI — 미주서안 +6.2%, 유주 +3.1%',
         '상하이발 미주서안 USD/FEU 2,950 돌파. 수출입 화주 모두 6월 단가 재산정 필요합니다. 홍해 리스크가 단기간 해소될 시그널이 없어 유럽향도 상승세 유지 전망.',
         1, 4*60+30),
        (5, '[질문] FCL 장기계약 NAC vs 스팟 — 어느 비율이 적정?',
         '미주향 월 30FEU 정도 보내는데, NAC 100%로 묶으면 운임 급락 시 손해, 스팟 100%면 성수기 피크 직격. 60/40으로 분산하는 게 일반적인지 궁금합니다.',
         NULL, 11*60+0),
        (6, '[경험] 부산 → LA 14일 → 도착 후 디머리지 폭탄',
         '컨테이너 게이트아웃 안 한 채로 4일 방치되니 일자당 USD 280, 총 USD 1,120. 콘솔 화물은 도착 알람 등록 필수입니다.',
         9, 18*60+15),
        (7, '[공유] 인천공항 → 프랑크푸르트 항공운임 5월 평균',
         '일반화물 GP USD 4.20/kg, 위험물 UN3481(리튬배터리) USD 7.80/kg. 6월 성수기 들어가면 USD 0.5~1.0 추가 인상 전망. 미리 케파 락 추천.',
         NULL, 27*60+45),
        (8, '[정보] 한진해운 사태 8년 — 그 이후 한국 선사 변화',
         'HMM은 정부 지분 정리 중. 컨테이너 1위(머스크), 2위(MSC), 3위(CMA-CGM)와 격차 크지만 한국 컨테이너 수출의 30% 이상이 여전히 HMM 통해 처리됩니다.',
         NULL, 36*60+0),
        (9, '[질문] LCL 콘솔 — 콘솔러 선택 기준',
         '저희는 1순위 트랜짓 정확도, 2순위 디머리지·체화 부담 정책, 3순위 단가입니다. 단가가 압도적으로 싸도 환적·B/L 분리 잘못하면 손실이 더 큽니다.',
         NULL, 44*60+30),
        (10, '[경고] 홍해 우회 — 케이프타운 루트로 12일 추가',
         '예멘 후티 공격 이후 머스크·하팍로이드 케이프타운 우회 지속. 부산-함부르크 평소 32일이 44일까지 늘어났습니다. 식품 콜드체인은 특히 영향 큼.',
         5, 54*60+15),
        (11, '[공유] 컨테이너 사이즈별 적재 가능 무게·부피 정리',
         '20DC: 28톤·33CBM / 40DC: 28톤·67CBM / 40HC: 28톤·76CBM / 45HC: 28톤·86CBM. 무거운 짐은 20피트, 가벼운 짐은 45피트가 단가 효율 우위.',
         NULL, 63*60+0),
        (12, '[질문] DDP 조건 — 수입국 VAT 처리 어떻게',
         'DDP인데 도착지 EU VAT를 누가 부담하나요? 계약서에 명시 안 했더니 분쟁 발생. 다들 DDP 견적 시 VAT 포함 여부 어떻게 명문화하시나요?',
         NULL, 72*60+30),
        (13, '[경험] 인천공항 콜드체인 화물 — 온도이탈 5회 클레임',
         '5°C 유지 화물이었는데 환적 중 8°C로 올라간 게 데이터로거에 찍힘. 항공사 보상 USD 12,000. 데이터로거 비용은 USD 50~100. 무조건 넣는 게 정답.',
         34, 84*60+15),
        (14, '[정보] 광양항 12월부터 자동 게이트 — 트럭 드라이버 신원 인증',
         '컨테이너 반출입 시 안면인식 게이트 도입. 운송사 사전 등록 필수. 기존 ID카드 게이트 6개월 병행 후 단일화.',
         NULL, 96*60+0),
        (15, '[공유] 환적(Transshipment) 시 발생하는 5가지 분실 패턴',
         '1)Mark 손상 2)팔레트 분리 적재 3)서류와 화물 분리 4)환적 항만 야적 5)최종 선박 적재 누락. CY-CY 직항이 더 비싸도 분실 리스크 낮아 권장.',
         NULL, 108*60+30),
        (16, '[질문] 해상보험 ICC(A) vs (B) vs (C) — 화주가 가입 시 어디?',
         '예전엔 (B) 가입이 일반적이었는데, 최근엔 (A) All Risk가 표준화되는 분위기. 보험료 차이는 5~10% 정도라 신상품·고가품은 (A) 가는 게 안전합니다.',
         NULL, 120*60+0),
        (17, '[경험] 인천항 → 닝보 환적 → 청두 — 도어투도어 23일',
         '청두 내륙 화주 배송. 인천→닝보 4일, 닝보 환적 3일, 닝보→청두 컨테이너 철도 12일, 통관·라스트마일 4일. 처음에는 14일로 견적 받았다가 두 배 됨.',
         NULL, 132*60+15),
        (18, '[정보] IMO 2026 — 컨테이너선 EEXI 강화 시행',
         '에너지 효율 등급 미달 선박은 감속운항 의무. 선사들이 슬로우 스티밍 도입 → 트랜짓 평균 +1~2일 늘어날 전망. 식품·패션 시즌 화물은 특히 영향.',
         NULL, 145*60+0),
        (19, '[공유] 부산 신항 vs 인천 신항 — 미주·동남아·중국 항로 우위',
         '미주 본선은 부산 압도적, 인천은 중국 환적·소량 화물 우위. 인천 신항이 LCL 콘솔 환경은 더 좋다는 게 현장 의견.',
         NULL, 158*60+30),
        (20, '[질문] 항공+해상 복합운송 SEA-AIR — 두바이 환적이 정답?',
         '부산→두바이 해상, 두바이→유럽 항공. 풀에어보다 30% 싸고, 풀시 대비 7~10일 단축. 단, 두바이 환적 박싱 변경 시 수수료 변동성 큼.',
         NULL, 172*60+0),
        (1, '[경험] CY → SD(Shipper Door) 트럭 배치 — 부산권 vs 수도권',
         '부산권은 트럭 단가 안정적, 수도권은 성수기(11~1월) 30% 이상 폭등. 수도권 출고 잦으면 운송사 장기 계약 강력 추천.',
         11, 185*60+15),
        (2, '[공유] D/O(Delivery Order) 처리 지연 — 한국 도착 후 1주 잠김 케이스',
         '서류상 결제 미확인 → D/O 발행 지연 → CY 보관료 일 USD 150. 결제·서류 처리 동시 진행이 핵심. 매년 반복되는 신입 실수.',
         NULL, 198*60+45),
        (4, '[정보] 한진 LA 터미널 — 컨테이너 회수 정체 5월 완화',
         '4월 평균 5일 회수가 5월 들어 3일로 단축. 트럭 드라이버 부족 일부 해소. 미주 화주들 회수 일정 단축 가능.',
         NULL, 212*60+0),
        (6, '[공유] FOB와 EXW 차이 — 수출자 책임 범위 한 줄 비교',
         'EXW: 공장 출하 시점 책임 종료(수출통관·운송 모두 바이어) / FOB: 본선 적재까지 수출자 책임. EXW 견적은 단가 싸 보이지만 바이어 측 부담이 매우 큼.',
         NULL, 225*60+30),
        (7, '[질문] 항공 화물 ULD 사이즈 — 어느 카테고리가 비용 효율?',
         'PMC(96×125") 사용률이 가장 높은데, 부피 화물은 LD3 컨테이너가 단가 효율 좋다는 의견. 인천-시카고 노선 비중 큰 분들 경험 부탁드립니다.',
         NULL, 240*60+0),
        (8, '[경험] 베트남 호치민 LCL — 트랜짓 9일이 14일로 늘어남',
         '광저우 환적 게이트 정체로 5일 추가. LCL은 직항이 거의 없어서 환적 리스크 늘 있습니다. 시즌 발주는 FCL 전환 강력 권장.',
         18, 254*60+15),
        (9, '[공유] 컨테이너 봉인(Seal) 종류 — Bolt vs Cable',
         'High Security Bolt Seal이 표준. Cable seal은 보안 약해 ISPS 항만에서 거부 사례 있음. 단가 차이 USD 1 안쪽이니 Bolt seal 통일 추천.',
         NULL, 268*60+0),
        (10, '[정보] CIQ 검역 강화 — 5월부터 가공식품 라벨 한자/영문 병기 요구',
         '중국 GACC 가공식품 수입 라벨 규정 강화. 한자+영문 표기 미흡 시 통관 보류. 기존 한자만 있어도 OK였지만 5월부터 영문 병기 필수.',
         NULL, 280*60+30),
        (11, '[공유] CFS 작업료 — 부산항 평균 단가 정리',
         '20DC USD 65, 40DC USD 110 수준. 콘솔러별 차이 USD 20~30. 콘솔 단가가 너무 싸면 CFS 작업료에서 뽑는 경우 많아 트로털 비교 필요.',
         NULL, 295*60+0),
        (12, '[질문] B/L Surrender vs Original — 언제 어느 걸 쓰시나요',
         '신뢰 바이어 + 빠른 인도 = Surrendered. 신규 거래 + 결제 미완료 = Original B/L. 잘못 발행하면 화물 인도 후 결제 못 받는 분쟁 발생.',
         NULL, 310*60+30),
        (13, '[경험] 인천 → JFK 항공 — 리튬배터리 UN3481 신고 누락 패널티',
         'IATA DGR 신고 누락으로 USD 5,000 페널티. 화주는 항공사가 알아서 처리하는 줄 알고 신경 안 썼던 케이스. 위험물은 무조건 사전 신고서 확보.',
         NULL, 322*60+0),
        (14, '[공유] 한국 → 호주 시드니 — 컨테이너 환경검역 AQIS',
         '호주는 컨테이너 외부도 검역 대상. 나무·흙·곤충 한 마리만 발견돼도 훈증 처리 USD 800. 출하 전 컨테이너 외부 세척 필수.',
         32, 335*60+15),
        (15, '[정보] 한국형 그린 항만 — 부산·인천 LNG 벙커링 인프라 확대',
         '2026년 부산·울산·인천 LNG 벙커링 가능 항만 확정. EU CBAM 대응 위해 친환경 연료 선박 비중 늘리는 글로벌 흐름. 한국 항만도 따라가는 중.',
         NULL, 350*60+0)
    ) AS t(member_id, title, content, photo_idx, minutes_ago)
),
ck AS (
    SELECT 1 AS go
    WHERE NOT EXISTS (
        SELECT 1 FROM tbl_post p
        JOIN tbl_community c ON c.id = p.community_id
        WHERE c.community_name = '해운물류 전문가 모임'
    )
),
ins AS (
    INSERT INTO tbl_post (member_id, community_id, post_status, title, content, created_datetime)
    SELECT (SELECT id FROM _gg_writers
            WHERE pos = ((src.member_id - 1) % (SELECT COUNT(*) FROM _gg_writers))::int + 1),
           (SELECT id FROM tbl_community WHERE community_name = '해운물류 전문가 모임'),
           'active'::post_status,
           src.title,
           src.content,
           now() - (src.minutes_ago * interval '1 minute')
    FROM src, ck
    RETURNING id, content
)
INSERT INTO tbl_post_file (post_id, file_id)
SELECT ins.id,
       (SELECT id FROM tbl_file
        WHERE file_path = '2026/05/20/community/post_' || lpad((src.photo_idx + 25)::text, 2, '0') || '.jpg')
FROM ins
JOIN src ON src.content = ins.content
WHERE src.photo_idx IS NOT NULL;

-- ------------------------------------------------------------
-- [5-4] FTA·관세 실무 스터디
-- ------------------------------------------------------------
WITH src AS (
    SELECT row_number() OVER () AS rn, t.*
    FROM (VALUES
        (4::bigint, '[공유] 한-EU FTA 원산지 자율증명제 — 인증수출자 신청 절차',
         '6,000유로 초과 거래는 인증수출자 번호 필수. 관세평가과 신청 → 평균 처리 4주. 직접 작성 가능해지면 매 건 원산지증명서 발급 비용 절감.',
         24, 6*60+0),
        (5, '[질문] HS코드 분쟁 — 관세평가심의위원회 신청 경험',
         '복합 소재 제품인데 관세사·수입자·세관 분류가 다 다릅니다. 평가위원회 신청 시 사전 자료 준비 어떻게 하셨는지?',
         NULL, 14*60+30),
        (6, '[경험] HS 8543.70 vs 8479.89 — 분류 차이로 관세 6%p 변동',
         '동일 제품인데 "전기제품"이냐 "기계제품"이냐 분류 다툼. 결국 8543.70으로 결정됐는데 관세율 8%→2%. HS코드 첫 4자리부터 신중하게.',
         NULL, 22*60+15),
        (7, '[공유] FTA 협정별 원산지 증명서 서식 정리',
         '한-미: KORUS-FTA C/O / 한-EU: Origin Declaration / 한-아세안: AK-FORM / RCEP: 통합 폼. 협정별 폼 잘못 쓰면 관세 환급 거부 사유.',
         NULL, 30*60+45),
        (8, '[정보] 관세청 — 환급 자동화 시스템 6월 본격 가동',
         'EL번호·신고필증·인보이스·B/L을 한 시스템에서 매칭. 기존 환급 평균 4주 → 1~2주 단축 전망. 환급 신청 누락 방지에도 효과.',
         NULL, 39*60+0),
        (9, '[질문] 직접운송원칙 — 환적 시 어디까지 인정되나',
         '한-아세안 FTA 직접운송원칙. 환적은 허용되지만 환적국에서 별도 가공 시 원산지 상실. 환적 국가에서 단순 보관·재포장 정도는 OK.',
         NULL, 48*60+30),
        (10, '[경험] 사후 추징 — 5년 지난 거래 원산지 증빙 요구',
         '관세청에서 2021년 거래 원산지 증빙 보완 요구. 인증수출자 폐지된 회사 자료라 확보 난항. 원산지 증빙은 무조건 5년 이상 보관 의무.',
         NULL, 58*60+0),
        (11, '[공유] BOM 기반 원산지 판정 — Material 단가 변동 시 재검증 필요',
         '원자재 가격 변동으로 역내가공 비율 60% 기준선 넘나드는 경우 발생. 분기마다 BOM 단가 재검증 안 하면 사후 추징 위험.',
         24, 67*60+45),
        (12, '[정보] WTO Tariff Database — 무료 활용 가이드',
         'WTO Tariff Download Facility(tariffdata.wto.org). 회원국별 HS코드별 기본관세·MFN·양허세율 다운로드. 신규 시장 검토 시 첫 단계로 활용.',
         NULL, 78*60+30),
        (13, '[질문] 보세창고 vs 자유무역지대 — 어느 게 절세 우위?',
         '재수출 비중 60% 이상이면 자유무역지대(인천·부산·광양)가 압도적. 보세창고는 단순 보관·재포장만 가능, FTZ는 제조·가공·연구개발까지 OK.',
         NULL, 88*60+0),
        (14, '[공유] 미국 USMCA — Steel & Aluminum 추가 요건',
         '자동차 부품 한국 → 멕시코 → 미국 흐름은 USMCA 직접 적용 안 됨. 멕시코 가공 시 70% 이상 북미산 강·알루미늄 요건 충족 필요.',
         NULL, 98*60+30),
        (15, '[경험] 원산지 사전심사 — KCS 신청 후 회신까지 8주',
         '복잡한 BOM 제품 사전심사 신청 → 회신 8주. 한 번 받아두면 5년 유효해 매 건 분쟁 없어집니다. 처음에는 시간 들지만 누적 효과 큼.',
         NULL, 110*60+0),
        (16, '[정보] CPTPP 가입 진행 — 한국 정부 2026 협상 재개',
         'CPTPP는 11개국 GDP 14%. 가입 시 일본·캐나다·호주 추가 시장 접근. 농산물 시장 개방 압력 vs 디지털·제조 수출 확대 trade-off.',
         NULL, 122*60+15),
        (17, '[질문] HS 4자리 결정 후 잔여 자리 분류 — 어떻게 접근?',
         '4자리는 GIR(General Rules of Interpretation)로 비교적 명확한데, 6자리·10자리 가면 세관마다 해석 차이. 관세사도 의견 갈리는 경우 많습니다.',
         NULL, 134*60+0),
        (18, '[공유] 한-중 FTA — 농수산물 양허 일정과 활용 품목',
         '한-중 FTA 발효 11년차. 양허 완성 단계 도달한 품목 활용 시 관세 0~3% 가능. 김·해조류·인삼 일부는 여전히 부분 양허 상태.',
         NULL, 146*60+30),
        (19, '[경험] FTA 원산지 위반 추징 사례 — 추징세 + 가산세 40%',
         '원산지 결정기준 미충족 적발 시 환급세 토해내는 건 기본, 부정 환급 가산세 40%까지. 의도 아니어도 입증 책임이 수입자에 있습니다.',
         NULL, 158*60+45),
        (20, '[정보] 한-인도 CEPA — 자동차부품 추가 양허 협상 진행',
         '11년 만에 추가 협상 재개. 자동차·전자부품 양허 폭 확대 논의. 인도 시장 노리는 한국 부품사들 관심 가져야 할 이슈.',
         NULL, 172*60+0),
        (1, '[공유] 환급 신청 — 가장 흔한 누락 사례 5가지',
         '1)EL번호 누락 2)품목별 환급 vs 정액환급 잘못 선택 3)6개월 신청 기한 도과 4)인보이스 통화 불일치 5)신고 가격 조정 누락. 매년 환급 누락액 수억 단위.',
         NULL, 184*60+30),
        (2, '[질문] EU CBAM 보고 — 우리는 부품 공급사인데도 영향?',
         'EU 바이어가 EE(임베디드 배출량) 자료 요구. 직접 대상은 아니지만 공급망 보고 요청 받는 사례 늘었습니다. 자발 제출하시는 분들 어떻게 데이터 수집하시나요?',
         16, 196*60+0),
        (3, '[공유] 협정 미충족 시 대체 옵션 — 보세가공·재수출감면',
         'FTA 원산지 못 맞추는 거래는 재수출감면제도 활용 검토. 일정 기간 내 재수출 조건으로 관세 면제. 단, 가공 단계 변경 시 원산지 변화 주의.',
         NULL, 210*60+30),
        (5, '[정보] 한국 — Authorized Economic Operator(AEO) 신규 인증',
         '24년 신규 AEO 인증 158개 사. 통관 신속화·검사 우대·해외 상호인정. 중견 이상 무역회사 안 받으면 경쟁사 대비 통관 속도 차이 큽니다.',
         NULL, 222*60+15),
        (6, '[경험] 관세 사후심사 — 거래 패턴 의심으로 전수조사 받음',
         '동일 품목 갑자기 단가 인상 → 관세평가 조사. 정상 거래 입증에 3개월. 단가 변동 시 사유서 미리 준비해두는 게 좋습니다.',
         NULL, 235*60+0),
        (7, '[공유] HS코드 — 신소재 제품 분류 가이드',
         '신소재 제품은 GIR 3(b) "본질적 특성" 기준 적용. 예: 탄소섬유 강화 플라스틱은 강화제 비중보다 매트릭스 비중이 본질. 분류 분쟁 최다 영역.',
         NULL, 248*60+30),
        (8, '[질문] 자율 원산지 증명 — 6,000유로 미만 거래 누가 진술서 보관?',
         '한-EU FTA 6,000유로 미만은 인증 없이 진술서 가능. 그런데 진술서 원본 보관 의무가 수출자/수입자 누구에 있는지 명확하지 않은 경우가 많습니다.',
         NULL, 262*60+0),
        (9, '[정보] RCEP 4년차 — 발효 이후 한국 활용률 통계',
         '관세청 통계상 RCEP 활용률 28%. 한-아세안 FTA(45%) 대비 낮음. 원산지 누적 기준 활용이 핵심인데 자료 준비 복잡해 활용도 낮은 것으로 분석.',
         NULL, 275*60+30),
        (10, '[공유] 관세 환급 단계 — 분기별 정리 vs 매건 신청',
         '소액·다건 거래는 분기 일괄 신청, 고액·소수 거래는 매건 신청이 효율적. 환급금 회수 속도와 인력 부담 trade-off.',
         NULL, 290*60+0),
        (11, '[질문] HS 9018 의료기기 — 식약처 인증과 통관 절차 동시 진행',
         '의료기기는 식약처 인증 종결 전 수입신고 불가. 인증 보류 시 보세창고 보관 비용 막대. 인증 처리 일정과 선적 일정 동기화 핵심.',
         NULL, 305*60+30),
        (12, '[경험] FTA 활용 — 첫 해 정착에 6개월',
         'FTA 활용 정착에 BOM 정비·원가표·원산지 결정기준 검토 등 6개월 소요. 중소기업은 관세법인 컨설팅(3~5백만 원 수준) 받는 게 결국 빠릅니다.',
         NULL, 320*60+0),
        (13, '[공유] 보세운송 신청 — 부산 → 평택 사례',
         '부산항 도착 → 평택 보세창고 보세운송. 신청서 KCS 단일전산망 제출, 평균 처리 1일. 부산 야적료 절감으로 컨테이너당 USD 200 정도 효과.',
         NULL, 335*60+0),
        (14, '[정보] WCO HS 2027 개정안 — 디지털 제품 분류 신설',
         'WCO 2027 개정안에서 디지털 상품·서비스 분류 신설 검토. 데이터·SaaS·콘텐츠 등 무형자산 무역 증가에 따른 대응.',
         NULL, 350*60+0)
    ) AS t(member_id, title, content, photo_idx, minutes_ago)
),
ck AS (
    SELECT 1 AS go
    WHERE NOT EXISTS (
        SELECT 1 FROM tbl_post p
        JOIN tbl_community c ON c.id = p.community_id
        WHERE c.community_name = 'FTA·관세 실무 스터디'
    )
),
ins AS (
    INSERT INTO tbl_post (member_id, community_id, post_status, title, content, created_datetime)
    SELECT (SELECT id FROM _gg_writers
            WHERE pos = ((src.member_id - 1) % (SELECT COUNT(*) FROM _gg_writers))::int + 1),
           (SELECT id FROM tbl_community WHERE community_name = 'FTA·관세 실무 스터디'),
           'active'::post_status,
           src.title,
           src.content,
           now() - (src.minutes_ago * interval '1 minute')
    FROM src, ck
    RETURNING id, content
)
INSERT INTO tbl_post_file (post_id, file_id)
SELECT ins.id,
       (SELECT id FROM tbl_file
        WHERE file_path = '2026/05/20/community/post_' || lpad((src.photo_idx + 25)::text, 2, '0') || '.jpg')
FROM ins
JOIN src ON src.content = ins.content
WHERE src.photo_idx IS NOT NULL;

-- ------------------------------------------------------------
-- [5-5] 무역금융 인사이트
-- ------------------------------------------------------------
WITH src AS (
    SELECT row_number() OVER () AS rn, t.*
    FROM (VALUES
        (5::bigint, '[공유] 신용장(L/C) Discrepancy 톱5 — 네고 거절 사유 통계',
         '한국 시중은행 네고 거절 사유: 1)Late shipment 32% 2)Inconsistent description 21% 3)Late presentation 17% 4)Goods description error 15% 5)Insurance error 8%. 처음 두 개로 70% 막을 수 있습니다.',
         NULL, 5*60+0),
        (6, '[질문] 환헤지 — 선물환 vs 통화옵션, 어느 단계에서 활용?',
         '월 거래액 USD 100만 이하면 선물환이 단순·저비용. 200만 넘어가면 콜·풋 옵션 조합으로 다운사이드만 헤지하는 게 효율적이라고 들었습니다. 실무 분들 의견?',
         22, 13*60+30),
        (7, '[정보] K-SURE — 단기수출보험 한도 자동 확대 신규 5천 사',
         '신용평가 BB- 이상 자동 확대 대상자 5,000개 사 통보 시작. 회사 인증서로 K-SURE 홈페이지 접속 후 확인 가능.',
         NULL, 22*60+15),
        (8, '[경험] L/C Transferable — 분할 양도 시 은행마다 해석 차이',
         '동일 LC를 한국·중국 공급사로 분할 양도. 한국 은행은 OK, 중국 통지은행은 거부. UCP 600 38조 해석이 은행 내부 룰에 따라 다릅니다.',
         NULL, 32*60+0),
        (9, '[공유] DDP 결제 — 부담 주체 명문화 안 했을 때 분쟁 사례',
         'DDP 가격에 VAT 포함 여부 분쟁. 계약서·인보이스에 "VAT inclusive" 또는 "VAT to be borne by Buyer" 명시 필수.',
         NULL, 41*60+45),
        (10, '[질문] 환율 1,500원 시대 — 환차익 vs 환차손 다 관리해야',
         '단순 환차익 누리는 단계 지났습니다. 마진 30% 챙겼는데 송금 시점 환율 30% 빠지면 다 날아갑니다. 어떤 회사는 매월 환율 락 정책 운영 중.',
         NULL, 51*60+30),
        (11, '[정보] 한은 5월 금리 — 동결 결정, 외환시장 영향',
         '미·한 금리차 200bp 유지. 원화 약세 압력 지속 전망. 수출 대금 송금은 즉시 환전, 수입 대금은 가능한 한 늦춤 — 일반 룰이지만 변동성 크면 의미 약해짐.',
         NULL, 62*60+0),
        (12, '[공유] D/P vs D/A — 회수 리스크 어디가 더 큰가',
         'D/P(Documents against Payment): 결제와 동시에 서류 인도, 상대적 안전. D/A(Documents against Acceptance): 서류 인도 후 만기 결제, 회수 리스크 큼. 신규 바이어엔 D/A 절대 비추.',
         NULL, 72*60+45),
        (13, '[질문] 무역금융 — 시중은행 vs 산업은행 vs 수출입은행 단가 비교',
         '동일 LC 매입 단가가 은행별 0.3~0.5%p 차이. 거래 볼륨 클수록 산은·수은이 우위. 작은 회사는 거래 시중은행과 우대금리 협상이 현실적.',
         NULL, 82*60+0),
        (14, '[공유] 외화 통장 운용 — USD·EUR·CNY 분산',
         '단일 통화 100% 보유는 환변동 직격. USD 60% / EUR 25% / CNY 15% 정도 분산 시 변동성 절반 수준. 회사 거래 통화 구성에 맞춰 비율 조정.',
         NULL, 92*60+30),
        (15, '[경험] 신용장 USANCE — 만기 90일 vs 180일 어느 게 유리?',
         '바이어는 길수록 좋아하고, 우리는 짧을수록 좋음. 90일 USANCE + USANCE 매입 할인료를 단가에 반영하는 게 일반적인 풀이.',
         NULL, 102*60+15),
        (16, '[정보] 한국무역보험공사 — Pre-Shipment 보험 한도 확대',
         '선적 전 단계 보험(Pre-Shipment)도 한도 확대. 바이어 신용 검증 어려운 신규 거래에서 효과 큼. 보험료 0.3~0.7% 수준.',
         NULL, 114*60+0),
        (17, '[질문] LC at Sight — 매입은행 처리 평균 몇 일?',
         '서류 접수 후 평균 3~5영업일. Discrepancy 0이면 3일, 1개라도 발견 시 7일 이상. 매입 빠른 은행 추천 받습니다.',
         NULL, 124*60+45),
        (18, '[공유] 환차익에 대한 회계 처리 — 영업외수익 vs 영업수익',
         '한국 GAAP·K-IFRS 기준 환차익은 영업외수익. 영업이익률 왜곡 방지를 위해 별도 보고가 정석. 환헤지 관련 손익도 동일.',
         NULL, 138*60+15),
        (19, '[정보] 무역보험 — 디지털 신청 시스템 6월 개편',
         'K-SURE 홈페이지 리뉴얼. 모바일 신청·계약서 전자서명 통합. 기존 PDF 양식 다운로드 → 출력 → 서명 → 업로드 흐름이 원클릭.',
         NULL, 150*60+0),
        (20, '[공유] PF(Project Finance) — 해외 EPC 프로젝트 자금 조달',
         '대형 EPC 수출 시 PF 구조. 산업은행·수출입은행이 보증 + 시중은행 신디케이트 론. 1억 달러 이상 프로젝트 표준 구조.',
         NULL, 162*60+30),
        (1, '[질문] 미국 바이어 ACH 결제 — Wire vs ACH 비용 비교',
         'Wire는 USD 25~50, ACH는 USD 0~5. 그러나 ACH는 미국 내 송금 한정. 미국 법인이 결제하는 구조라면 ACH가 압도적 저렴.',
         NULL, 175*60+0),
        (2, '[경험] 첫 LC — Documentary Credit 51조 함정',
         '바이어가 51조 "Reimbursement Bank"를 본인 거래은행이 아닌 곳으로 지정. 결제 처리 7일 지연. 51조 항목 검토 무시하면 안 됩니다.',
         NULL, 188*60+30),
        (3, '[공유] Standby L/C — 일반 L/C와 어떻게 다른가',
         '일반 L/C는 결제 도구, Standby L/C는 보증 도구. 바이어가 기한 내 결제 못 하면 발행은행이 대지급. 미국·중동 EPC 프로젝트 표준.',
         NULL, 200*60+0),
        (4, '[질문] 환위험 관리 — 일반 SMB는 어디까지 가능?',
         '연 매출 100억대 SMB는 매월 결제일 정해놓고 그 시점 환율로 한 번에 환전하는 게 현실적. 옵션·NDF는 비용 효율 안 나옴.',
         NULL, 212*60+15),
        (5, '[정보] 글로벌 결제 — Wise·Payoneer 활용 한국 회사 늘어남',
         '아마존·이베이 해외 매출 정산에 Wise·Payoneer 활용. 전통 SWIFT 송금 대비 수수료 1/3 수준. 단, 거래액 한도와 KYC 절차 변동성 큼.',
         NULL, 225*60+0),
        (6, '[공유] 인보이스 디스카운팅 — 매출채권 조기 회수',
         '바이어 결제 만기 전 매출채권을 은행에 양도하고 90% 즉시 회수. 금리 5~8%(연환산). 자금 회수 빠르지만 마진 일부 양도.',
         NULL, 238*60+30),
        (7, '[질문] LC 분쟁 — UCP 600 ICC 중재 활용 경험',
         '서류 검증 분쟁이 발행은행·통지은행 간 안 풀려서 ICC DOCDEX 신청. 평균 처리 6주, 비용 USD 1만 수준. 분쟁 금액 USD 5만 이상이면 의미.',
         NULL, 252*60+0),
        (8, '[경험] 위장 LC — 가짜 발행은행 사례 회피',
         '"ABC Bank Cayman Islands" 명의 LC 받았는데 SWIFT BIC 조회 결과 미등록. 통지은행이 거부. 발행은행 신뢰성 검증 핵심.',
         NULL, 264*60+30),
        (9, '[공유] 한국 외환신고 — 1만 달러 이상 송금 시 한은 신고',
         '연간 누적 USD 1만 초과 송금은 한국은행 외국환신고 필요. 자영업자·SMB가 자주 놓치는 부분. 누적 관리 시스템 필요.',
         NULL, 277*60+0),
        (10, '[정보] EBRD·ADB — 한국 중소기업 무역금융 프로그램',
         '유럽부흥개발은행(EBRD)·아시아개발은행(ADB) 신흥국 무역금융 한국 기업 활용 가능. 신흥국 LC 보증 / 단가 우대 / 한도 확대.',
         NULL, 290*60+30),
        (11, '[질문] 외환 — Forward Contract 만기 전 해지 비용',
         '6개월 선물환 계약했는데 거래 취소로 3개월 시점 해지 필요. 해지 수수료 + 환율 차이 정산 비용. 사전 시뮬레이션 안 하면 손실 큼.',
         NULL, 304*60+0),
        (12, '[공유] 무역보험 — 부보율 90% 활용 시 절세 효과',
         '단기수출보험 부보율 90% 활용 시, 미회수 발생해도 90% 보전. 보험료는 비용 인정 → 절세 효과까지. 사실상 회수 리스크 보장 + 절세 일석이조.',
         NULL, 318*60+15),
        (13, '[경험] 신용장 51조 누락 — 결제 처리 1주 지연',
         'LC 51조(Reimbursement) 항목 누락. 발행은행이 통지은행과 정산 절차 별도 진행. 결제일 1주 지연. 51조까지 다 봐야 합니다.',
         NULL, 332*60+30)
    ) AS t(member_id, title, content, photo_idx, minutes_ago)
),
ck AS (
    SELECT 1 AS go
    WHERE NOT EXISTS (
        SELECT 1 FROM tbl_post p
        JOIN tbl_community c ON c.id = p.community_id
        WHERE c.community_name = '무역금융 인사이트'
    )
),
ins AS (
    INSERT INTO tbl_post (member_id, community_id, post_status, title, content, created_datetime)
    SELECT (SELECT id FROM _gg_writers
            WHERE pos = ((src.member_id - 1) % (SELECT COUNT(*) FROM _gg_writers))::int + 1),
           (SELECT id FROM tbl_community WHERE community_name = '무역금융 인사이트'),
           'active'::post_status,
           src.title,
           src.content,
           now() - (src.minutes_ago * interval '1 minute')
    FROM src, ck
    RETURNING id, content
)
INSERT INTO tbl_post_file (post_id, file_id)
SELECT ins.id,
       (SELECT id FROM tbl_file
        WHERE file_path = '2026/05/20/community/post_' || lpad((src.photo_idx + 25)::text, 2, '0') || '.jpg')
FROM ins
JOIN src ON src.content = ins.content
WHERE src.photo_idx IS NOT NULL;

-- ------------------------------------------------------------
-- [5-6] 무역 IT·디지털 혁신
-- ------------------------------------------------------------
WITH src AS (
    SELECT row_number() OVER () AS rn, t.*
    FROM (VALUES
        (6::bigint, '[공유] B/L 전자화(eB/L) — 한국 무역 디지털화 현황',
         '국제해사위원회(BIMCO) FIT Alliance 가입 선사 확대. 한국 HMM·SM Lines도 동참. 종이 B/L 대비 발급 1초, 비용 90% 절감. 다만 수입국 세관 수용도가 변수.',
         18, 5*60+30),
        (7, '[질문] 무역 ERP — SAP B1 vs Odoo vs 자체 개발',
         '연 매출 100억대 무역회사. SAP B1은 라이선스 부담 크고, Odoo는 커스터마이즈 자유. 자체 개발은 6개월~1년. 다들 어디서 출발하셨나요?',
         NULL, 14*60+0),
        (8, '[정보] 한국 무역협회 KITA — AI 바이어 매칭 서비스 오픈',
         'tradeNAVI에 AI 매칭 추가. 회사 카탈로그 업로드 → 글로벌 바이어 매칭 추천. 무료 5건/월. 신규 시장 발굴 시 워밍업 도구로 활용.',
         NULL, 23*60+15),
        (9, '[공유] 무역 자동화 — Zapier로 알리바바 RFQ 자동 응답',
         '알리바바 RFQ 메일 → Zapier 워크플로 → ChatGPT API로 1차 응답 → 영업팀 검토. 응답 시간 24시간 → 30분 단축. 전환율 +18%.',
         NULL, 33*60+45),
        (10, '[질문] 무역 데이터 분석 — Tableau vs Power BI 비교',
         '관세청 신고 데이터·자사 매출·환율을 결합해서 대시보드. Tableau는 시각화 강점, Power BI는 MS 생태계 통합 강점. 무역회사는 어디가 적합?',
         NULL, 44*60+0),
        (11, '[경험] 블록체인 B/L — 머스크 TradeLens 종료 후 대안',
         'IBM·머스크 합작 TradeLens 23년 종료. 현재 대안은 GSBN(글로벌해운컨소시엄). 한국 HMM·일본 ONE·중국 COSCO 참여. 채택률 아직 낮음.',
         NULL, 54*60+30),
        (12, '[정보] 한국 디지털통상협정 KDTA — 추진 현황',
         '디지털 통상 협정 8개국 추진 중. 데이터 국경 이동·전자상거래·디지털 ID 인정. 한-싱 DPA 발효, 한-EU 협상 진행.',
         NULL, 65*60+0),
        (13, '[공유] 무역 SaaS — Flexport·Freightos·ShipBob 등 글로벌 톱5',
         'Flexport(통합 포워딩), Freightos(운임 비교), ShipBob(3PL), Project44(가시성), FourKites(트래킹). 한국 도입은 ShipBob·Project44 비중 높음.',
         NULL, 76*60+30),
        (14, '[질문] OCR — 인보이스·B/L 자동 인식 솔루션',
         'Amazon Textract·Google Document AI·국내 NHN·뤼이드. 무역 서식 학습은 한국 SaaS가 정확도 우위. 월 처리량 1만 건 넘으면 라이선스 단가 비교 필수.',
         NULL, 88*60+0),
        (15, '[경험] ChatGPT 활용 — 영문 메일 응대 시간 70% 단축',
         '바이어 RFQ → ChatGPT 초안 → 영업팀 검토·발송. 시간 70% 절감, 응답률 +25%. 단, 가격·납기 등 핵심 수치는 사람이 반드시 검토.',
         NULL, 100*60+45),
        (16, '[정보] CBAM EU 통합 시스템 — Carbon Footprint 자동화',
         'EU 6월부터 CBAM 보고 자동화 포털 오픈. 한국 수출기업이 EU 바이어 요구에 응해야 할 데이터 구조 정리. 자동화 안 하면 매 분기 반복 노동.',
         NULL, 112*60+15),
        (17, '[공유] EDI(전자문서교환) — 한국 KTNET vs 외국 시스템',
         'KTNET이 한국 표준. 글로벌 GS1·VAN 시스템과 호환 매핑 필요. 대형 바이어(월마트·코스트코)는 자체 EDI 강요. 표준 변환 미들웨어 핵심.',
         NULL, 124*60+0),
        (18, '[질문] 화상 영업 — Zoom·Teams·Webex 어느 게 효과적?',
         '미국·유럽 바이어는 Zoom 압도적, 중동·아세안은 Teams 비중 높음. 중국 바이어는 텐센트 미팅 강요하는 경우 다수. 다중 도구 운영 필수.',
         NULL, 136*60+30),
        (19, '[경험] 무역 자동화 도입 — ROI 6개월',
         '월 발주 200건 수동 처리 → RPA 도입. 초기 비용 1,200만 원, 인건비 절감으로 6개월 만에 회수. 1년차 ROI 200%.',
         NULL, 148*60+0),
        (20, '[정보] 한국 — 무역 데이터 표준화 추진 K-Trade',
         '관세청·산업부 합동 무역 데이터 표준화 프로젝트. 27년까지 전 신고서 디지털 단일창구. 종이 신고 1% 미만 목표.',
         NULL, 160*60+15),
        (1, '[공유] CRM — 무역 회사용 Pipedrive vs HubSpot vs Zoho',
         'Pipedrive: 영업 파이프라인 단순·직관 / HubSpot: 마케팅 자동화 통합 / Zoho: 무역·재고 통합. 단가 차이 큼. 50명 미만 회사는 Pipedrive 가성비.',
         19, 172*60+0),
        (2, '[질문] 디지털 마케팅 — LinkedIn vs Google Ads 무역 B2B',
         'LinkedIn은 의사결정자 직접 도달, CPC 비싸나 전환 우위. Google Ads는 트래픽 다량, 정성 떨어짐. 우리는 두 채널 비율 7:3 운영.',
         NULL, 185*60+30),
        (3, '[정보] 한국 — 디지털 무역 단일창구(UTC) 본격 가동',
         '관세청 UTC 6월 본격 가동. 신고·환급·증명서 발급 단일 포털. 무역회사 IT팀은 API 연동 사전 준비 필요.',
         NULL, 198*60+0),
        (4, '[공유] BI 대시보드 — 무역 KPI 시각화 5종',
         '월별 수출액·바이어별 매출·국가별 성장률·환율 영향·LC 매입 회전. 이 5개만 대시보드로 띄워도 의사결정 속도 2배. Power BI 무료 버전으로 충분.',
         NULL, 210*60+45),
        (5, '[질문] 사이버 보안 — 무역회사 BEC(비즈니스 이메일 사기)',
         '바이어 메일 도용 → 송금 계좌 변경 안내 → 거액 송금 후 사기 적발. 한국 회사 작년 피해 2,000억 원대. MFA·도메인 검증 필수.',
         NULL, 224*60+0),
        (6, '[경험] AI 번역 — DeepL vs 구글번역 정확도 비교',
         '무역 계약서 번역에서 DeepL 정확도가 구글 대비 우위. 단, 법률 용어는 여전히 사람 검토 필수. 1차 초안 시간 90% 단축.',
         NULL, 236*60+30),
        (7, '[정보] 인도 — DPDP(데이터 보호법) 시행 영향',
         '23년 시행 DPDP. 한국 → 인도 데이터 이전 동의·로컬라이제이션 요건. SaaS 활용 무역회사는 인도 바이어 데이터 처리 시 동의 필수.',
         NULL, 250*60+0),
        (8, '[공유] 무역회사 IT 보안 표준 — ISO 27001 도입 가이드',
         '글로벌 바이어 ISO 27001 요구 증가. 도입 비용 5천만~1억, 인증 유효 3년. 컨설팅 통합 패키지가 효율적.',
         NULL, 263*60+15),
        (9, '[질문] 무역회사 IT 인력 — 외주 vs 자체 운영',
         '연 매출 200억 미만은 외주 효율, 그 이상은 자체 1~2명 + 외주 병행이 일반적. 핵심 데이터는 내부 보유 필수.',
         NULL, 276*60+30),
        (10, '[공유] 데이터 마이그레이션 — 기존 ERP → 신규 시스템',
         '레거시 ERP에서 신규 시스템으로 데이터 이관. 매핑·정합성·테스트에 평균 6개월. 비즈니스 중단 없이 진행하려면 단계적 컷오버 필수.',
         NULL, 290*60+0),
        (11, '[경험] 무역 챗봇 — 24/7 바이어 응대로 리드 +40%',
         '회사 홈페이지 GPT 기반 챗봇. 영어·중국어·스페인어 동시 응답. 야간/주말 리드 +40% 증가. 챗봇 응답에서 실제 영업 전환율 12%.',
         NULL, 303*60+30),
        (12, '[정보] AI Act EU — 무역 AI 시스템 영향',
         'EU AI Act 24년 발효, 26년 본격 시행. 신용평가·생체인식 AI 고위험 분류. 무역회사 자체 AI 운영 시 위험 평가 의무.',
         NULL, 318*60+0),
        (13, '[공유] 사이버 침해 — 무역회사 평균 피해액 USD 240만',
         'IBM 보고서 기준 글로벌 무역회사 평균 피해 USD 240만. 한국은 USD 120만 수준. 보안 투자 ROI는 1:8.',
         NULL, 332*60+30),
        (14, '[질문] 무역 자동화 — 도입 우선순위',
         '인보이스 OCR / 메일 분류 / 견적 자동화 / 데이터 대시보드 / RPA. 5개 중 무엇부터? 우리는 OCR 1순위로 시작했는데 효과 만점.',
         NULL, 348*60+0)
    ) AS t(member_id, title, content, photo_idx, minutes_ago)
),
ck AS (
    SELECT 1 AS go
    WHERE NOT EXISTS (
        SELECT 1 FROM tbl_post p
        JOIN tbl_community c ON c.id = p.community_id
        WHERE c.community_name = '무역 IT·디지털 혁신'
    )
),
ins AS (
    INSERT INTO tbl_post (member_id, community_id, post_status, title, content, created_datetime)
    SELECT (SELECT id FROM _gg_writers
            WHERE pos = ((src.member_id - 1) % (SELECT COUNT(*) FROM _gg_writers))::int + 1),
           (SELECT id FROM tbl_community WHERE community_name = '무역 IT·디지털 혁신'),
           'active'::post_status,
           src.title,
           src.content,
           now() - (src.minutes_ago * interval '1 minute')
    FROM src, ck
    RETURNING id, content
)
INSERT INTO tbl_post_file (post_id, file_id)
SELECT ins.id,
       (SELECT id FROM tbl_file
        WHERE file_path = '2026/05/20/community/post_' || lpad((src.photo_idx + 25)::text, 2, '0') || '.jpg')
FROM ins
JOIN src ON src.content = ins.content
WHERE src.photo_idx IS NOT NULL;

-- ------------------------------------------------------------
-- [5-7] K-Food 수출 클럽
-- ------------------------------------------------------------
WITH src AS (
    SELECT row_number() OVER () AS rn, t.*
    FROM (VALUES
        (7::bigint, '[공유] 라면 수출 — 2026년 1분기 1.3억 달러 돌파',
         '농식품부 통계상 라면 수출 사상 최고. 미국·중국·일본 3대 시장 매출 +40% 이상. 신라면·진라면 외 매운 라면 라인업이 글로벌 트렌드 주도.',
         13, 5*60+0),
        (8, '[질문] FDA 등록 — 식품시설 등록 vs 사전신고 차이',
         '미국 FDA Facility Registration은 시설 등록(연 1회 갱신), Prior Notice는 매 선적 사전신고. 두 가지 다른 요건이지만 헷갈리는 분 많아요.',
         NULL, 14*60+30),
        (9, '[경험] 김 수출 — 미국 NRT(미주식품박람회) 부스 운영 후기',
         '김 단독 부스 + 시식 코너 운영. 첫 부스 비용 USD 18,000, 매칭 바이어 60개 사. 그중 실제 거래 전환 12개 사. 부스 위치(통로 측)가 결정적.',
         12, 23*60+15),
        (10, '[정보] EU 식품 인증 — Novel Food 신청 절차',
         '한국 전통식품도 EU 신규 시장에 처음 들어가면 Novel Food 분류. EFSA 심사 평균 18개월. 곤약·홍삼 일부 품목 적용.',
         NULL, 32*60+45),
        (11, '[공유] HALAL 인증 — 한국 KMF 인증과 말레이시아 JAKIM 호환성',
         'KMF(한국이슬람협회) 인증은 국내·아세안 일부에서 인정. 본격 중동 진출은 말련 JAKIM 또는 두바이 EIAC. 인증 비용 1천만 원 내외.',
         NULL, 42*60+0),
        (12, '[질문] 콜드체인 — 김치 수출 시 LCL vs FCL 선택',
         '김치는 발효 온도 관리가 핵심. LCL은 환적·온도 노출 리스크. FCL Reefer 컨테이너로 단독 적재가 안전. 단가는 LCL의 3배.',
         NULL, 51*60+30),
        (13, '[정보] 일본 — 한국 식품 수입 절차와 라벨링 요건',
         '일본 식품위생법 라벨링: 원재료명·식품첨가물·내용량·유통기한 일본어 표기 필수. 한국어 병기 OK. 알레르겐 28종 별도 강조.',
         NULL, 61*60+15),
        (14, '[공유] 한국 떡볶이 — 미국·유럽 시장 성장세 폭발',
         '미국 떡볶이 매출 2024년 대비 2026년 1분기 +320%. 글로벌 PB(자체 브랜드) 떡볶이도 등장. 즉석 떡볶이 키트 형태가 가장 선호.',
         NULL, 71*60+45),
        (15, '[경험] 콜드체인 운송 — 항공 vs 해상 Reefer 비교',
         '딸기·신선 농산물은 항공이 사실상 유일. 가공식품·김치는 해상 Reefer로 충분. 단가는 항공이 해상 대비 8~10배.',
         NULL, 82*60+0),
        (16, '[정보] 호주 — 식품 수입 라벨링 CoOL(원산지표시) 의무',
         '호주 모든 식품 라벨에 원산지 시각적 표시. "Made in Korea" 텍스트 + 비율 막대그래프. 위반 시 통관 거부 또는 벌금.',
         NULL, 92*60+30),
        (17, '[질문] 인도네시아 — BPOM ML 등록과 라벨링 비용',
         'BPOM ML 신청 평균 6~9개월. 등록 비용 IDR 5,000만~1억(약 한화 400~800만 원). 라벨링 변경 시 별도 갱신 필요.',
         NULL, 102*60+45),
        (18, '[공유] K-소스 — 고추장·간장 수출 가공식품 가이드',
         '미국 FDA: 고추장은 Acidified Food / 일본: 가공조미료 / EU: 식품 첨가물 규제. 같은 제품이라도 시장별 분류 다름.',
         NULL, 113*60+0),
        (19, '[경험] 동남아 진출 — 베트남·인니·말련·태국 4국 동시 진출',
         '4국 동시 진출 시 각국 인증 비용·시간 트레이드오프. 우리는 인니 BPOM 우선(시장 최대) → JAKIM 확장 전략. 6개월간 인증 7건.',
         12, 124*60+30),
        (20, '[정보] 한국 농수산식품유통공사(aT) — 수출 마케팅 지원사업',
         'K-Food 마케팅 패키지: 시장조사·박람회·SNS 마케팅 통합 지원. 중소 수출기업 우선. 5월 신청 마감 D-15.',
         NULL, 136*60+15),
        (1, '[공유] 글로벌 K-Food 트렌드 — 비건·할랄·글루텐프리 동시 충족',
         '미국 밀레니얼·Z세대 식품 트렌드. 식물성 라면·할랄 김치·글루텐프리 떡 라인업 확장 중. 인증 비용 부담 크지만 단가 우위.',
         NULL, 148*60+0),
        (2, '[질문] 미국 OTC 등록 — 건강기능식품 vs 일반 식품 분류',
         '홍삼·인삼은 미국 OTC가 아닌 Dietary Supplement(DSHEA). 한국 건강기능식품 인증과 별도. NDI(New Dietary Ingredient) 신청 필요한 경우 다수.',
         NULL, 160*60+30),
        (3, '[경험] 두바이 식품 박람회 Gulfood — 한국관 운영',
         '연 1회 2월 두바이. 한국관 60개 사 참여, 매칭 800회. 중동·아프리카 바이어 일괄 만남. 부스 단가 USD 6,000(2024 기준).',
         33, 174*60+0),
        (4, '[정보] EU 식품 검역 — 잔류농약 기준 강화',
         'EU 농약 잔류허용기준(MRL) 매년 강화. 작년 적용된 클로피랄리드는 한국 농산물에 영향. 수출 전 잔류농약 사전 검사 필수.',
         NULL, 186*60+30),
        (5, '[공유] HACCP 인증 — 한국 vs 미국 vs EU 차이',
         '기본 7원칙 12절차 공통. 미국은 FSMA로 확장(예방관리). EU는 BRC·IFS 등 민간 표준 병행. 한국 HACCP만으로 글로벌 모두 인정 안 됨.',
         NULL, 198*60+45),
        (6, '[질문] 식품 박람회 — SIAL Paris vs Anuga vs FoodEx Japan',
         'SIAL: 가공식품 / Anuga: 신선식품 강세 / FoodEx Japan: 아시아 시장 진출 최적. 우리 제품 타겟에 따라 선택.',
         NULL, 212*60+15),
        (7, '[경험] 중동 진출 — UAE 두바이 매트 매장 입점',
         '두바이 카르푸·럴루·스피니즈 3대 매트 입점. 입점 보증금 USD 5,000, 슬로팅 USD 2,000. 첫 6개월 매출 회수 후 본격 영업.',
         NULL, 224*60+30),
        (8, '[정보] 캐나다 — CFIA 식품 라벨링 양국어 의무',
         '캐나다는 영어·프랑스어 양국어 표기 의무. 모르고 들여왔다가 통관 후 라벨 재인쇄 비용 발생. 첫 진출 시 라벨 양국어 디자인 필수.',
         NULL, 238*60+0),
        (9, '[공유] K-드링크 수출 — 알로에·식혜·수정과 글로벌 시장',
         '한국 전통 음료 글로벌 시장 성장. 알로에 음료 미국·중남미 강세, 식혜·수정과 동남아 확장. 무알콜·저당 트렌드 부합.',
         NULL, 252*60+30),
        (10, '[질문] 호치민 식품 박람회 Food&Hotel Vietnam — 참가 가치?',
         '호치민 5월 개최. 베트남 외 캄·라·미얀마 바이어 참여. 한국 식품 부스 매년 30개 사 이상. 단가 USD 4,000 수준.',
         NULL, 266*60+0),
        (11, '[경험] 김치 수출 — 컨테이너 발효 온도 관리 실패 사례',
         '20FT Reefer 0°C 세팅했는데 환적 중 정전 → 8°C 노출 2일. 김치 과발효로 전량 폐기. USD 35,000 손실. 데이터로거 필수.',
         NULL, 280*60+15),
        (12, '[정보] 한식진흥원 — 글로벌 한식당 인증 사업',
         '해외 한식당 인증으로 K-Food 브랜드 강화. 인증 한식당이 한국 식자재 우선 수입. B2B 수출에 시너지 큼.',
         NULL, 294*60+30),
        (13, '[공유] 곤약 — 일본 시장 한국산 점유율 확대',
         '일본 시장 한국산 곤약 점유율 28%. 일본 자국 생산 감소로 한국 의존도 높아짐. 단, 일본은 자국산 우선 정책 강화 움직임.',
         NULL, 308*60+0),
        (14, '[질문] 미국 — Acidified Food 분류 시 21 CFR 114 적용',
         '고추장·김치 일부 미국에서 Acidified Food로 분류. 21 CFR 114에 따라 thermal process 검증 + 시설 등록 필수. 컨설팅 USD 5,000~8,000.',
         NULL, 322*60+30),
        (15, '[경험] K-Food 박람회 — 시식 코너 운영 효과',
         '부스 운영 시 시식 코너 있으면 매칭 +200%. 비용은 USD 1,500~3,000 추가지만 ROI 압도적. 직접 맛 보여주는 게 결정적.',
         NULL, 340*60+0)
    ) AS t(member_id, title, content, photo_idx, minutes_ago)
),
ck AS (
    SELECT 1 AS go
    WHERE NOT EXISTS (
        SELECT 1 FROM tbl_post p
        JOIN tbl_community c ON c.id = p.community_id
        WHERE c.community_name = 'K-Food 수출 클럽'
    )
),
ins AS (
    INSERT INTO tbl_post (member_id, community_id, post_status, title, content, created_datetime)
    SELECT (SELECT id FROM _gg_writers
            WHERE pos = ((src.member_id - 1) % (SELECT COUNT(*) FROM _gg_writers))::int + 1),
           (SELECT id FROM tbl_community WHERE community_name = 'K-Food 수출 클럽'),
           'active'::post_status,
           src.title,
           src.content,
           now() - (src.minutes_ago * interval '1 minute')
    FROM src, ck
    RETURNING id, content
)
INSERT INTO tbl_post_file (post_id, file_id)
SELECT ins.id,
       (SELECT id FROM tbl_file
        WHERE file_path = '2026/05/20/community/post_' || lpad((src.photo_idx + 25)::text, 2, '0') || '.jpg')
FROM ins
JOIN src ON src.content = ins.content
WHERE src.photo_idx IS NOT NULL;

-- ------------------------------------------------------------
-- [5-8] K-Beauty 글로벌
-- ------------------------------------------------------------
WITH src AS (
    SELECT row_number() OVER () AS rn, t.*
    FROM (VALUES
        (8::bigint, '[공유] 미국 MoCRA — 화장품 시설 등록 2026 기준',
         'Modernization of Cosmetics Regulation Act. 시설 등록·제품 신고·라벨링·안전성 입증 의무. 등록 안 하면 통관 거부. 7월 강제 적용.',
         15, 6*60+0),
        (9, '[질문] EU CPNP 등록 — Responsible Person 누가 맡나',
         'EU 화장품 책임자(RP)는 EU 거주자/법인이어야 함. 한국 회사 단독 진출 시 EU 컨설팅 회사 위임이 일반적. 비용 월 USD 200~500.',
         NULL, 15*60+30),
        (10, '[경험] 중국 NMPA — 색조 vs 기능성 등록 비용 비교',
         '일반 화장품 NMPA 비안(Filing): 4~6개월 / 특수 화장품(미백·자외선차단·염모): 12~18개월. 특수 등록 비용 RMB 30~50만.',
         NULL, 25*60+0),
        (11, '[정보] 미국 — SPF 자외선차단제는 OTC Drug 분류',
         '미국 자외선차단제는 OTC Drug. FDA 모노그래프 준수 + GMP 시설 등록. 한국 일반 화장품 면허로 못 들어감. 미국 SPF 등록 비용 USD 5만+.',
         NULL, 35*60+30),
        (12, '[공유] 동남아 진출 — 4국 화장품 인증 비교 표',
         '인니 BPOM(6~9개월) / 말련 NPRA(3~6개월) / 태국 FDA(3~5개월) / 베트남 CDA(2~4개월). 한국 화장품 KFDA 신고증 있으면 단축 적용.',
         16, 46*60+15),
        (13, '[질문] 라벨링 — 다국어 OBL(Outer Box Label) 디자인 가이드',
         '한국 라벨 + 영문 + 진출국 언어. 4개국 동시 진출 시 단상자 디자인 6면 활용. 디자인 회사와 1차부터 다국어 가이드라인 공유 필수.',
         NULL, 56*60+30),
        (14, '[경험] 인플루언서 마케팅 — 베트남 KOL 협업 ROI',
         '베트남 인스타 팔로워 30만 KOL 협업. 비용 USD 3,000, 단일 캠페인 매출 USD 28,000. ROI 9배. KOL 선택 시 진정성 + 한국 화장품 사용 이력 우선.',
         17, 67*60+0),
        (15, '[정보] 중국 — 광군제·6.18 매출 한국 화장품 비중',
         '24년 광군제 천묘 한국 화장품 매출 RMB 18억. 동남아 직구 비중 +30%. 디지털 채널 중심 시장 변화 가속.',
         NULL, 78*60+15),
        (16, '[공유] 사우디 SFDA — 화장품 인증 절차',
         'SFDA 등록 평균 4~6개월. SASO Saudi Standard 라벨링. 사우디·UAE 동시 진출 시 GCC 화장품 규정 일괄 검토 추천.',
         NULL, 90*60+0),
        (17, '[질문] 일본 — 야쿠지호(藥事法) 화장품과 의약외품 구분',
         '일본은 화장품·의약외품(쥰야쿠힌) 구분. 미백·여드름 등 효능 강조 시 의약외품. 약사법 신고 별도 + 광고 표현 제한.',
         NULL, 102*60+30),
        (18, '[정보] 미국 — Sephora·Ulta·Target K-Beauty 카테고리 강화',
         '미국 대형 뷰티 유통 3사 K-Beauty 카테고리 별도 운영. 입점 시 슬로팅 USD 3~5만. 입점 후 매대 위치·디스플레이 비용 별도.',
         NULL, 114*60+0),
        (19, '[공유] OEM/ODM — 한국 코스맥스·콜마 vs 신규 OEM 비교',
         '대형 OEM은 최소 발주량 부담, 신규 OEM은 가격 우위 but 품질 변동. MOQ 5,000개 미만은 신규, 그 이상은 대형 추천.',
         NULL, 126*60+30),
        (20, '[경험] 아랍에미리트 진출 — 두바이 Sephora 입점 후기',
         '두바이 Sephora 입점 6개월. 진열 보증금 USD 1만, 매대 비용 별도. 매출 USD 25만 달성. UAE·GCC 시장 진입 거점.',
         NULL, 138*60+15),
        (1, '[질문] EU CPNP — Responsible Person 회사 추천',
         'EU 진출 시 RP 위임 회사. 독일·프랑스·네덜란드 위주. 단가는 비슷한데 응대 속도 차이 큼. 추천 회사 있으시면 댓글 부탁.',
         NULL, 152*60+0),
        (2, '[공유] K-스킨케어 — 미국 Gen Z 매출 +180% 성장',
         '미국 Gen Z 시장 K-스킨케어 매출 폭발. TikTok·인스타 영향. 7-Step 루틴이 글로벌 표준으로 자리. 마스크팩 카테고리 최대 강세.',
         16, 164*60+30),
        (3, '[정보] 한국 — 화장품 안전성 평가 의무 시행',
         '한국 식약처 화장품 안전성 평가 의무화. 글로벌 트렌드 따라 한국도 안전성 입증 책임 강화. 새 제품 출시 시 추가 비용.',
         NULL, 178*60+0),
        (4, '[경험] 중국 광군제 — Tmall Global K-Beauty 부스 운영',
         '광군제 Tmall Global 한국 화장품 부스. 사전 마케팅 RMB 50만 투자, 24시간 매출 RMB 280만. ROI 5.6배.',
         NULL, 190*60+30),
        (5, '[공유] 동남아 — TikTok Shop 화장품 시장 폭발',
         '베트남·인니·필리핀 TikTok Shop 화장품 카테고리 폭발 성장. 한국 화장품 입점 진입장벽 낮음. CPM·CPC 1/3 수준.',
         NULL, 204*60+0),
        (6, '[질문] 사우디 — 화장품 광고 제재 사항',
         '사우디는 화장품 광고에서 모델 노출·종교적 표현 제한. SASO 광고 가이드라인. 위반 시 광고 금지 + 벌금.',
         NULL, 216*60+45),
        (7, '[정보] EU — Microplastics 화장품 규제',
         'EU 27년부터 화장품 마이크로비드 전면 금지. 한국 화장품 EU 수출 시 미리 대체 성분 전환 필요. 환경 인증 가점.',
         NULL, 230*60+0),
        (8, '[공유] 글로벌 마케팅 — Sephora·Ulta·Riley Rose 차이',
         'Sephora: 중·고가 / Ulta: 중저가 / Riley Rose: Z세대 타깃. 한국 화장품 가격대별 적합 채널 다름.',
         NULL, 244*60+30),
        (9, '[경험] 멕시코 — Sephora·Sears 매대 입점',
         '멕시코 시티 Sephora·Sears 매대 입점. 라티노 시장 한국 화장품 인기 폭발. 매대 비용 USD 1만/월. 매출 안정화 6개월.',
         NULL, 258*60+15),
        (10, '[질문] 한-EU FTA — 화장품 관세 0% 효과',
         '한-EU FTA로 한국 화장품 EU 관세 0%. 원산지 증명서만 갖추면 가격 경쟁력 큼. 인증수출자 등록 필수.',
         NULL, 272*60+0),
        (11, '[정보] 중국 — 화장품 비안(Filing) 신규 절차 간소화',
         '24년 NMPA 화장품 비안 절차 일부 간소화. 일반 화장품 신청 비용 RMB 5,000~15,000. 특수 화장품은 여전히 복잡.',
         NULL, 286*60+30),
        (12, '[공유] 글로벌 — 비건·할랄·크루얼티프리 동시 충족 트렌드',
         '글로벌 화장품 시장 비건·할랄·크루얼티프리 통합 인증 트렌드. 한국 OEM 다수 이 인증 보유. 단가 영향 미미하지만 매출 +20~30%.',
         NULL, 300*60+0),
        (13, '[질문] 중동 — UAE·사우디·카타르 동시 진출 비용',
         'UAE 단독 인증 USD 5,000, 사우디 USD 8,000, 카타르 USD 4,000. GCC 통합 인증 검토 시 USD 10,000.',
         NULL, 314*60+30),
        (14, '[경험] 베트남 — TikTok Shop 한국 화장품 매출 +500%',
         '베트남 TikTok Shop 한국 화장품 상위 셀러. 단가 USD 5~15 범위 마스크팩·립밤·세럼. 인플루언서 협업으로 매출 폭증.',
         NULL, 328*60+0),
        (15, '[정보] 일본 — 한국 화장품 매출 사상 최고',
         '24년 일본 한국 화장품 수입 USD 8억 돌파. 매대·로프트·돈키호테 모두 한국 화장품 메인 진열. K-Beauty 시즌 1년 내내.',
         NULL, 340*60+30)
    ) AS t(member_id, title, content, photo_idx, minutes_ago)
),
ck AS (
    SELECT 1 AS go
    WHERE NOT EXISTS (
        SELECT 1 FROM tbl_post p
        JOIN tbl_community c ON c.id = p.community_id
        WHERE c.community_name = 'K-Beauty 글로벌'
    )
),
ins AS (
    INSERT INTO tbl_post (member_id, community_id, post_status, title, content, created_datetime)
    SELECT (SELECT id FROM _gg_writers
            WHERE pos = ((src.member_id - 1) % (SELECT COUNT(*) FROM _gg_writers))::int + 1),
           (SELECT id FROM tbl_community WHERE community_name = 'K-Beauty 글로벌'),
           'active'::post_status,
           src.title,
           src.content,
           now() - (src.minutes_ago * interval '1 minute')
    FROM src, ck
    RETURNING id, content
)
INSERT INTO tbl_post_file (post_id, file_id)
SELECT ins.id,
       (SELECT id FROM tbl_file
        WHERE file_path = '2026/05/20/community/post_' || lpad((src.photo_idx + 25)::text, 2, '0') || '.jpg')
FROM ins
JOIN src ON src.content = ins.content
WHERE src.photo_idx IS NOT NULL;

-- ------------------------------------------------------------
-- [5-9] 자동차부품 글로벌 거래
-- ------------------------------------------------------------
WITH src AS (
    SELECT row_number() OVER () AS rn, t.*
    FROM (VALUES
        (9::bigint, '[공유] 한국 자동차부품 수출 — 전기차 비중 35% 돌파',
         '관세청 24년 자동차부품 수출 USD 230억. 전기차 부품 비중 35%로 사상 최고. 배터리·모터·인버터 중심 성장. 내연기관 부품 단계적 축소.',
         20, 5*60+0),
        (10, '[질문] IATF 16949 인증 — 신규 취득 비용과 기간',
         '자동차부품 OEM 진출 필수. 인증 비용 5천~1억, 기간 6~12개월. 한국 인증기관 KSR·KMR·LRQA 중 선택. 비용 차이 미미.',
         NULL, 14*60+30),
        (11, '[정보] 멕시코 USMCA — 자동차 부품 원산지 75% 요건',
         'USMCA 자동차 본체 원산지 75%. 한국 → 멕시코 → 미국 흐름은 멕시코 가공도가 핵심. 부품도 70% 북미산 강·알루미늄 의무.',
         NULL, 23*60+15),
        (12, '[경험] 인도 OEM 진출 — Tata·Mahindra Tier 2 진입',
         '인도 자동차 OEM Tata·Mahindra·Maruti. Tier 2 진입 시 첫 6개월 PPAP 승인 절차. 인증 통과율 60% 수준.',
         21, 33*60+0),
        (13, '[공유] 자동차 OEM PPAP — Production Part Approval Process',
         'PPAP 5단계 승인. Level 1~5 차이는 제출 자료 깊이. 미국 빅3는 Level 3 표준. 한국 부품사 첫 진출 시 Level 3로 준비.',
         NULL, 43*60+45),
        (14, '[질문] 전기차 배터리 — 셀·모듈·팩 어디부터 진출?',
         '셀(LG에너지솔루션·삼성SDI·SK온 독점) 진입 어려움. 모듈·팩·BMS는 중소 부품사 진입 여지. 단, 안전 인증(UN38.3·UL 1973) 필수.',
         NULL, 54*60+30),
        (15, '[경험] 독일 BMW 1차 협력사 진출 — 5년 걸림',
         'BMW Tier 1 진입까지 5년. 초기 R&D 협업·시제품 평가·소량 생산·전체 모델 양산 4단계. 인내 게임. 단가 우위만으론 안 됨.',
         NULL, 65*60+0),
        (16, '[정보] 미국 인플레이션감축법(IRA) — 한국 자동차부품 영향',
         'IRA 적용 전기차 세액공제 한국 부품 비중 강화. 한국 → 미국 직접 수출 또는 한국 → 멕시코 → 미국 흐름이 IRA 인센티브 대상.',
         NULL, 76*60+15),
        (17, '[공유] 자동차부품 EAR(미국 수출통제) — 군용 듀얼 유의',
         '센서·반도체 부품은 EAR 듀얼 유즈 가능. 미국 수출 시 ECCN 분류 필수. 군용 우려 시 라이선스. 위반 시 수출 금지 + 벌금.',
         NULL, 87*60+0),
        (18, '[질문] 전기차 충전기 — 미국 NEMA 인증 vs UL 인증',
         'EV 충전기 미국 시장 진출 시 NEMA·UL 동시 필요. NEMA는 사양, UL은 안전. 한국 KS 인증과 별도. 비용 USD 3~5만.',
         NULL, 98*60+30),
        (19, '[경험] 중국 EV 부품 — BYD·니오 진출 도전',
         '중국 EV 시장 BYD 30% 점유율. Tier 2 진출 시 가격 경쟁 극심. 한국 부품사 강점은 품질·신뢰성. 단가 20%↑여도 받아줌.',
         NULL, 110*60+0),
        (20, '[정보] 자동차 칩 — 글로벌 공급망 재편',
         '인피니언·NXP·르네사스 3강 + 한국 SK하이닉스·삼성. 자동차 반도체 단가 +30% 인상. 한국 자동차 OEM 부품사 영향.',
         NULL, 122*60+30),
        (1, '[공유] 자동차부품 HS코드 — 8708 vs 8504 vs 8542 분류',
         '엔진 부품 8708, 전기 모터 8501, 배터리 8507, 센서 9031. 잘못 분류 시 관세 5~8%p 차이. HS 6자리부터 신중.',
         NULL, 134*60+0),
        (2, '[질문] 폴란드 — 한국 자동차부품 진출 거점화',
         '폴란드 LG에너지솔루션·삼성SDI 진출 후 한국 부품사 동반 진출 가속. 폴란드 노동력·EU 시장 접근성 강점.',
         NULL, 146*60+30),
        (3, '[정보] EU CBAM — 자동차부품 직접 대상은 아니지만',
         'CBAM 직접 대상은 철강·알루미늄·시멘트. 자동차부품은 간접 영향(원자재 EE 보고). 한국 부품사도 자료 제출 준비.',
         NULL, 158*60+0),
        (4, '[경험] 미국 빅3 — GM·포드·스텔란티스 진입 차이',
         'GM 가장 까다로움(품질 인증), 포드 중간, 스텔란티스 신규 진입 우호적. 진출 시 우선순위 검토.',
         NULL, 170*60+15),
        (5, '[공유] 자동차부품 환경 인증 — 글로벌 PFAS 규제',
         'EU·미국 PFAS 규제 강화. 자동차 도장·가스켓 포함된 PFAS 단계적 금지. 대체 소재 R&D 시급.',
         NULL, 182*60+30),
        (6, '[질문] 자동차부품 — Just-In-Time vs Just-In-Sequence',
         'JIT: 정해진 시간 도착 / JIS: 조립 순서대로 도착. JIS는 더 까다롭지만 단가 우위. 한국 부품사 미국 OEM 진입 시 JIS 요구 늘어남.',
         NULL, 195*60+0),
        (7, '[정보] 인도 EV 시장 — 26년 폭발 성장 전망',
         '인도 EV 시장 26년 25% 성장 전망. Mahindra·Tata 자체 EV 라인업 확장. 한국 부품사 진입 골든타임.',
         NULL, 207*60+30),
        (8, '[공유] 자동차부품 품질 인증 — APQP vs PPAP 차이',
         'APQP는 신제품 개발 단계, PPAP는 양산 승인 단계. APQP 4단계 → PPAP 승인 → 양산. 빅3 표준.',
         NULL, 220*60+0),
        (9, '[경험] 베트남 — VinFast 진출 후기',
         '베트남 VinFast Tier 2 진입. 가격·품질 압박 극심, but 매출 확대 기회. 한국 부품사 중 VinFast 진출 30여 사.',
         NULL, 232*60+30),
        (10, '[질문] 자동차부품 — 미국 NHTSA 안전 인증',
         '미국 NHTSA FMVSS 안전 규제. 부품별 규정 별도. 위반 시 리콜·생산 중단. 사전 인증 비용 USD 5~10만.',
         NULL, 245*60+0),
        (11, '[정보] 한국 — 자동차부품 R&D 지원사업 신청',
         '산업부 자동차부품 R&D 지원사업. 미래차 부품·전동화 부품 우선. 한 기업당 최대 5억. 신청 6월 마감.',
         NULL, 258*60+30),
        (12, '[공유] 자동차부품 단가 인상 — 어떻게 풀어내는가',
         '원자재 인상·환율 변동·인건비 인상. OEM 단가 협상 매년 11~12월. 인상 사유 데이터 기반으로 제시 필수.',
         NULL, 272*60+0),
        (13, '[질문] 자동차부품 보세가공 — 한국 → 멕시코 흐름',
         '한국 부품 → 멕시코 보세가공 → 미국 수출. 보세가공 시설 인증 필요. 멕시코 IMMEX 프로그램과 결합.',
         NULL, 285*60+30),
        (14, '[경험] 일본 도요타 — Tier 1 진입 도전 10년',
         '도요타 Tier 1 진입까지 10년. 일본 자동차 부품 시장 진입장벽 가장 높음. 일본어 의사소통·일본식 품질 관리 핵심.',
         NULL, 298*60+0),
        (15, '[정보] 글로벌 EV 시장 — 26년 한국 부품사 점유율 확대 전망',
         '한국 부품사 EV 점유율 +5%p 전망. LG·삼성·SK 배터리 중심에 협력사 확장. 매출 다변화 골든타임.',
         32, 312*60+30),
        (16, '[공유] 자동차 부품 디지털화 — IATF + ISO 27001 동시 인증',
         '자동차 사이버보안 강화. IATF 16949 + ISO 27001 + ISO 21434 통합 인증 트렌드. 비용 1억+, 기간 1년+.',
         NULL, 326*60+0),
        (17, '[질문] 자동차부품 — 글로벌 환경 규제 PFAS·POPs 대응',
         'EU·미국·중국 PFAS·POPs 단계적 금지. 자동차 부품 대체 소재 R&D. 한국 부품사 26~27년 핵심 과제.',
         NULL, 340*60+0)
    ) AS t(member_id, title, content, photo_idx, minutes_ago)
),
ck AS (
    SELECT 1 AS go
    WHERE NOT EXISTS (
        SELECT 1 FROM tbl_post p
        JOIN tbl_community c ON c.id = p.community_id
        WHERE c.community_name = '자동차부품 글로벌 거래'
    )
),
ins AS (
    INSERT INTO tbl_post (member_id, community_id, post_status, title, content, created_datetime)
    SELECT (SELECT id FROM _gg_writers
            WHERE pos = ((src.member_id - 1) % (SELECT COUNT(*) FROM _gg_writers))::int + 1),
           (SELECT id FROM tbl_community WHERE community_name = '자동차부품 글로벌 거래'),
           'active'::post_status,
           src.title,
           src.content,
           now() - (src.minutes_ago * interval '1 minute')
    FROM src, ck
    RETURNING id, content
)
INSERT INTO tbl_post_file (post_id, file_id)
SELECT ins.id,
       (SELECT id FROM tbl_file
        WHERE file_path = '2026/05/20/community/post_' || lpad((src.photo_idx + 25)::text, 2, '0') || '.jpg')
FROM ins
JOIN src ON src.content = ins.content
WHERE src.photo_idx IS NOT NULL;

-- ------------------------------------------------------------
-- [5-10] 친환경·에너지 무역
-- ------------------------------------------------------------
WITH src AS (
    SELECT row_number() OVER () AS rn, t.*
    FROM (VALUES
        (10::bigint, '[공유] EU CBAM — 26년 본격 적용, 한국 수출기업 대응 가이드',
         'CBAM 25년 보고 의무 → 26년 인증서 매입 의무. 철강·알루미늄·시멘트·비료·전력·수소 직접 대상. 한국 수출기업 EE 산정·검증 시스템 구축 필수.',
         27, 5*60+30),
        (1, '[질문] 태양광 모듈 — 미국 시장 IRA 인센티브 적용 받는 방법',
         '미국 IRA 태양광 모듈 세액공제. 한국산 모듈도 미국 내 부착·조립 비중 일정 이상이면 적용. 단, 셀 단계가 핵심. 한국 셀 → 미국 모듈화 흐름이 정답.',
         NULL, 14*60+0),
        (2, '[경험] 베트남 풍력 — 한국 부품 공급 사례',
         '베트남 남부 빈투안 풍력단지 한국산 발전기·블레이드 공급. 한국 두산에너빌리티·효성중공업 등 진출. 매출 USD 5천만 단위.',
         26, 23*60+15),
        (3, '[정보] EU — Renewable Energy Directive(RED III)',
         'EU REDIII 45% 재생에너지 목표. 한국 친환경 부품 수요 증가. 풍력·태양광·수소 전체 카테고리 진출 기회.',
         NULL, 33*60+0),
        (4, '[공유] 수소 — 한국 → 호주·중동 그린수소 협력',
         '한국 두산·SK·롯데 호주·UAE 그린수소 사업. 한국 수소 부품·기술 수출 가속. 26~30년 산업 폭발 성장.',
         NULL, 42*60+45),
        (5, '[질문] ESG 보고 — 한국 중소기업 어디부터 시작?',
         '글로벌 바이어 ESG 보고 요구 확대. GRI 표준 기준 시작 추천. 환경·사회·지배구조 3축. 중소기업은 환경 자료부터 정리.',
         NULL, 53*60+30),
        (6, '[정보] 미국 IRA — 한국 배터리 부품 점유율 +40%',
         '미국 IRA 시행 후 한국 배터리 부품 점유율 폭발 성장. LG·삼성·SK가 미국 현지 공장 확장. 한국 협력사 동반 진출.',
         NULL, 64*60+0),
        (7, '[경험] 폴란드 — LG 배터리 공장 동반 진출',
         '폴란드 브로츠와프 LG에너지솔루션 공장 인근에 한국 부품사 진출. 30여 사 동반. 인건비·EU 시장 접근성 강점.',
         NULL, 75*60+15),
        (8, '[공유] 태양광 — 미국 UFLPA 한국 패널 영향',
         '미국 UFLPA(위구르 강제노동 방지법). 중국 신장 폴리실리콘 사용 제품 통관 차단. 한국산 폴리실리콘·셀이 IRA + UFLPA 우위.',
         NULL, 86*60+30),
        (9, '[질문] CBAM — 한국 중견 수출기업 보고 비용 부담',
         'CBAM 보고서 1건당 컨설팅 USD 5~8천. 분기당 1회 = 연 USD 2~3만 부담. 자동화 시스템 도입 시 USD 50만+. 어떻게 풀어가시나요?',
         NULL, 98*60+0),
        (10, '[정보] 한국 — 그린뉴딜 2.0 추진',
         '정부 그린뉴딜 2.0 발표. 친환경 에너지 분야 R&D·수출 지원 강화. 중견·중소 기업 우선. 신청 6월부터.',
         NULL, 110*60+30),
        (11, '[공유] 풍력 블레이드 — 운송 노하우',
         '풍력 블레이드 길이 60~80m. 특수 차량·선박 필요. 한국 → 유럽 운송 단가 USD 50~80만/세트. 운송이 단가의 30%.',
         NULL, 122*60+0),
        (12, '[경험] 호주 — 그린수소 한국 협력 사업',
         '호주 퍼스·다윈 그린수소 단지 한국 두산 협력. 호주 풍부한 햇빛·바람으로 그린수소 생산. 한국 수소 활용 시설.',
         NULL, 134*60+15),
        (13, '[질문] 친환경 인증 — RE100·CDP 한국 기업 가입 단계',
         'RE100(재생에너지 100%) 한국 기업 30여 사. CDP(탄소 공시) 한국 200여 사. 글로벌 바이어가 가입 여부를 거래 조건으로 요구하는 사례 늘어남.',
         NULL, 146*60+0),
        (14, '[정보] 한국 K-ETS — 26년 강화',
         'K-ETS(한국 배출권거래제) 26년 강화. 무상할당 축소 → 유상 비중 확대. 에너지 다소비 기업 부담 증가. 친환경 전환 가속 압박.',
         NULL, 157*60+30),
        (15, '[공유] 폴리실리콘 — 한국·중국·미국 시장 점유율',
         '폴리실리콘 글로벌 시장 중국 75%, 한국 OCI 5%, 미국 Hemlock 3%. 한국 산업부 폴리실리콘 R&D 강화 중. 미국 UFLPA 호재.',
         NULL, 170*60+0),
        (16, '[질문] 친환경 무역 — Carbon Footprint Tracker 솔루션',
         '글로벌 친환경 무역 보고용 Carbon Footprint 측정 SaaS. Watershed·Persefoni·Sphera. 한국 중소 도입 시 단가 USD 3~5만/년.',
         NULL, 182*60+30),
        (17, '[경험] 사우디 — 한국 태양광 모듈 단가 협상',
         '사우디 네옴 프로젝트 한국 태양광 모듈 공급. 단가 협상에 1년+. 중국과 가격 경쟁 심화, but 품질 우위로 진입.',
         NULL, 194*60+0),
        (18, '[정보] 미국 — 청정에너지 보조금 30년까지 보장',
         'IRA 청정에너지 보조금 30년까지 보장. 정권 교체 가능성에도 의회 통과 법안. 장기 투자 안정성 확보.',
         NULL, 206*60+45),
        (19, '[공유] 전기차 충전기 — 한국·중국·미국·유럽 표준 차이',
         '한국 CHAdeMO/CCS Combo, 미국 NACS(Tesla)·CCS, 유럽 CCS, 중국 GB/T. 모듈 호환성·인증 다 다름. 진출 시 표준 맞춤형 설계.',
         NULL, 220*60+0),
        (20, '[질문] 탄소 인증 — Verra vs Gold Standard 차이',
         'Verra: 가장 일반적, 수량 우위 / Gold Standard: 까다로움, 단가 우위. 글로벌 바이어가 인증 종류로 가격 차등.',
         NULL, 232*60+30),
        (1, '[정보] EU — Battery Passport 의무화',
         'EU 27년부터 배터리 패스포트 의무. 배터리 라이프사이클 데이터 추적. 한국 배터리 수출 시 추가 데이터 시스템 필요.',
         NULL, 245*60+0),
        (2, '[경험] 중동 — 사우디·UAE 태양광 진출',
         '사우디 NEOM·UAE Masdar 한국 태양광 모듈 공급. 사막 환경 특화 모듈 R&D 필요. 한국 OCI·한화솔루션 진출.',
         NULL, 258*60+30),
        (3, '[공유] 친환경 컨테이너 운송 — Bio-LNG·메탄올 선박',
         '머스크·CMA-CGM·하팍로이드 친환경 연료 선박 발주. 한국 HMM도 27년까지 메탄올 선박 12척 도입. 친환경 화물 단가 가산.',
         NULL, 270*60+0),
        (4, '[질문] 한국 — 수소 충전소 시장 진출 사례',
         '한국 수소 충전소 27년까지 1,500기 목표. 한국 수소 부품사 동반 성장. SK·효성·코오롱 진출. 중소 부품사 기회.',
         NULL, 283*60+15),
        (5, '[정보] EU — Critical Raw Materials Act',
         'EU CRMA 핵심 광물 공급망 다변화. 중국 의존 축소. 한국·일본·호주 협력 확대. 한국 광물 가공 기술 진출 기회.',
         NULL, 296*60+0),
        (6, '[경험] 일본 — 한국 풍력 발전기 진출 시도',
         '일본 풍력 시장 한국 두산·효성 진출. 일본 자체 메이커(미쓰비시·도시바) 강세. 한국은 가격·납기 우위.',
         NULL, 308*60+30),
        (7, '[공유] EU — Sustainable Finance Disclosure Regulation(SFDR)',
         'EU SFDR 금융기관 친환경 투자 공시 의무. 한국 친환경 수출기업이 EU 금융기관 자금 유치 시 SFDR 요건 부합 필수.',
         NULL, 320*60+0),
        (8, '[질문] 친환경 무역 — 한국 중소기업 진출 우선 순위',
         'EV 부품 > 태양광 > 풍력 > 수소 > 친환경 소재 순으로 한국 중소기업 진출 적합도 평가. 단계적 진출 전략 추천.',
         NULL, 335*60+0)
    ) AS t(member_id, title, content, photo_idx, minutes_ago)
),
ck AS (
    SELECT 1 AS go
    WHERE NOT EXISTS (
        SELECT 1 FROM tbl_post p
        JOIN tbl_community c ON c.id = p.community_id
        WHERE c.community_name = '친환경·에너지 무역'
    )
),
ins AS (
    INSERT INTO tbl_post (member_id, community_id, post_status, title, content, created_datetime)
    SELECT (SELECT id FROM _gg_writers
            WHERE pos = ((src.member_id - 1) % (SELECT COUNT(*) FROM _gg_writers))::int + 1),
           (SELECT id FROM tbl_community WHERE community_name = '친환경·에너지 무역'),
           'active'::post_status,
           src.title,
           src.content,
           now() - (src.minutes_ago * interval '1 minute')
    FROM src, ck
    RETURNING id, content
)
INSERT INTO tbl_post_file (post_id, file_id)
SELECT ins.id,
       (SELECT id FROM tbl_file
        WHERE file_path = '2026/05/20/community/post_' || lpad((src.photo_idx + 25)::text, 2, '0') || '.jpg')
FROM ins
JOIN src ON src.content = ins.content
WHERE src.photo_idx IS NOT NULL;

-- ============================================================
-- 6) 사진 보강 — 각 커뮤니티 사진 첨부 게시글 ~15개 목표
--    (작성 시 NULL 처리된 photo_idx 보정 / 멱등)
-- ============================================================
DO $balance_photos$
DECLARE
    cnames CONSTANT text[] := ARRAY[
        '글로벌 수출 포럼','수입 바이어 네트워크','해운물류 전문가 모임','FTA·관세 실무 스터디',
        '무역금융 인사이트','무역 IT·디지털 혁신','K-Food 수출 클럽','K-Beauty 글로벌',
        '자동차부품 글로벌 거래','친환경·에너지 무역'
    ];
    cname text;
    cid bigint;
    current_photos int;
    need int;
    p_rec record;
    photo_idx int := 25;  -- 26~60 순환 (시작 직전 값)
    fid bigint;
BEGIN
    FOREACH cname IN ARRAY cnames LOOP
        SELECT id INTO cid FROM tbl_community WHERE community_name = cname;
        IF cid IS NULL THEN CONTINUE; END IF;

        SELECT COUNT(*) INTO current_photos
        FROM tbl_post_file pf
        JOIN tbl_post p ON p.id = pf.post_id
        WHERE p.community_id = cid;

        need := 15 - current_photos;
        IF need <= 0 THEN CONTINUE; END IF;

        FOR p_rec IN
            SELECT p.id
            FROM tbl_post p
            LEFT JOIN tbl_post_file pf ON pf.post_id = p.id
            WHERE p.community_id = cid AND pf.post_id IS NULL
            ORDER BY p.created_datetime
            LIMIT need
        LOOP
            -- 26..60 범위 순환: ((photo_idx - 26 + 1) % 35) + 26
            photo_idx := ((photo_idx - 25) % 35) + 26;
            SELECT id INTO fid FROM tbl_file
            WHERE file_path = '2026/05/20/community/post_' || lpad(photo_idx::text, 2, '0') || '.jpg';
            IF fid IS NOT NULL THEN
                INSERT INTO tbl_post_file (post_id, file_id) VALUES (p_rec.id, fid);
            END IF;
        END LOOP;
    END LOOP;
END $balance_photos$;

COMMIT;

-- ============================================================
-- 검증 쿼리
-- ============================================================
SELECT '=== community.sql 적재 결과 ===' AS info;

SELECT c.id, c.community_name,
       (SELECT COUNT(*) FROM tbl_community_member cm WHERE cm.community_id = c.id) AS members,
       (SELECT COUNT(*) FROM tbl_post p WHERE p.community_id = c.id) AS posts,
       (SELECT COUNT(*) FROM tbl_post p JOIN tbl_post_file pf ON pf.post_id = p.id WHERE p.community_id = c.id) AS posts_with_photo,
       (SELECT cf.id FROM tbl_community_file cf WHERE cf.community_id = c.id) AS thumb_file_id
FROM tbl_community c
WHERE c.community_name IN (
    '글로벌 수출 포럼','수입 바이어 네트워크','해운물류 전문가 모임','FTA·관세 실무 스터디',
    '무역금융 인사이트','무역 IT·디지털 혁신','K-Food 수출 클럽','K-Beauty 글로벌',
    '자동차부품 글로벌 거래','친환경·에너지 무역')
ORDER BY c.id;
