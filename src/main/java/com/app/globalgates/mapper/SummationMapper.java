package com.app.globalgates.mapper;

import com.app.globalgates.domain.video_chat.SummationVO;
import com.app.globalgates.dto.video_chat.SummationDTO;
import org.apache.ibatis.annotations.Mapper;

import java.util.Optional;

@Mapper
public interface SummationMapper {
    // 요약본 등록
    public void insert(SummationVO summationVO);

    // 요약본 조회
    public Optional<SummationVO> selectById(Long id);
}
