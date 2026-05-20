package com.app.globalgates.repository.video_chat;

import com.app.globalgates.domain.video_chat.SummationVO;
import com.app.globalgates.mapper.SummationMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
@RequiredArgsConstructor
public class SummationDAO {
    private final SummationMapper summationMapper;

    // 요약본 등록
    public void save(SummationVO summationVO) {
        summationMapper.insert(summationVO);
    }

    // 요약본 조회
    public Optional<SummationVO> findById(Long id) {
        return summationMapper.selectById(id);
    }
}
