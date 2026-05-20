-- 멤버(id 7~26) ↔ 카테고리 매핑 시드
-- 사용법: psql -U globalgates -d globalgates -f member_category_seed.sql
-- 특징:
--   * tbl_member 에는 category 컬럼이 없음. M:N 관계 테이블에 INSERT.
--   * category_name 으로 JOIN → 환경별 category id 차이에 안전.
--   * BEGIN/COMMIT + 사전 DELETE 로 멱등(반복 실행 가능).

BEGIN;

-- 7~26 범위 기존 매핑 제거 (멱등성)
DELETE FROM tbl_member_category_rel WHERE member_id BETWEEN 7 AND 26;

INSERT INTO tbl_member_category_rel (member_id, category_id)
SELECT v.member_id, c.id
FROM (VALUES
    -- 7 김재호: Semicom Korea 해외영업 → 수출, IT, 반도체
    (41,  '수출'), (41,  'IT'), (41,  '반도체'),
    -- 8 이수민: Lumiere Cosmetic → 수출, 화장품
    (42,  '수출'), (42,  '화장품'),
    -- 9 박지원: Korea Food World 수출 → 수출, 식품, 가공식품
    (43,  '수출'), (43,  '식품'), (43,  '가공식품'),
    -- 10 정태영: Ulsan AutoParts → 수출, 자동차, 자동차부품
    (44, '수출'), (44, '자동차'), (44, '자동차부품'),
    -- 11 최예나: EcoFabric 수출 MD → 수출, 섬유/의류
    (45, '수출'), (45, '섬유/의류'),
    -- 12 한승우: FTA 컨설턴트 → 관세, FTA
    (46, '관세'), (46, 'FTA'),
    -- 13 윤채린: 관세사 인천공항 통관 → 관세, 통관
    (47, '관세'), (47, '통관'),
    -- 14 임도현: 국제물류 → 물류
    (48, '물류'),
    -- 15 강나영: Global Marketing → 무역서비스
    (49, '무역서비스'),
    -- 16 오재민: 무역금융 → 금융, 무역금융
    (50, '금융'), (50, '무역금융'),
    -- 17 송지안: 동남아 자문 호치민 → 무역서비스, 동남아
    (51, '무역서비스'), (51, '동남아'),
    -- 18 배현우: EuroTech 함부르크 → 수입, 유럽
    (52, '수입'), (52, '유럽'),
    -- 19 노유진: Chemical 원료수입 → 수입, 원자재, 화학원료
    (53, '수입'), (53, '원자재'), (53, '화학원료'),
    -- 20 황민호: MachineWorks 해외영업 → 수출, 기계/장비
    (54, '수출'), (54, '기계/장비'),
    -- 21 신예린: 수출보험 K-SURE → 금융, 보험
    (55, '금융'), (55, '보험'),
    -- 22 권태우: 포워더 FCL/LCL/항공 → 물류, 해운, 항공
    (56, '물류'), (56, '해운'), (56, '항공'),
    -- 23 조하늘: Digital Trade Hub → IT, 플랫폼
    (57, 'IT'), (57, '플랫폼'),
    -- 24 양시우: Fresh Farm 수출 → 수출, 식품, 농산물
    (58, '수출'), (58, '식품'), (58, '농산물'),
    -- 25 문가은: HealthGlobal Med RA → 의료기기
    (59, '의료기기'),
    -- 26 백선호: 중남미 통상 KOTRA → 미주, 무역서비스
    (60, '미주'), (60, '무역서비스')
) AS v(member_id, cat_name)
JOIN tbl_category c ON c.category_name = v.cat_name;

-- 검증: 멤버별 매핑된 카테고리 리스트
SELECT m.id,
       m.member_nickname,
       string_agg(c.category_name, ', ' ORDER BY c.id) AS categories
FROM tbl_member m
LEFT JOIN tbl_member_category_rel r ON r.member_id = m.id
LEFT JOIN tbl_category c ON c.id = r.category_id
WHERE m.id BETWEEN 40 AND 61
GROUP BY m.id, m.member_nickname
ORDER BY m.id;

COMMIT;
