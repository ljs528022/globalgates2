package com.app.globalgates.mapper;

import com.app.globalgates.domain.FileRecodingVO;
import com.app.globalgates.domain.MeetingVO;
import com.app.globalgates.dto.FileRecodingDTO;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.List;
import java.util.Optional;

@Mapper
public interface FileRecodingMapper {
    // 녹음 파일 등록
    public void insert(FileRecodingVO recodingVO);

    // 회의 id와 유저 id로 모든 녹화파일 조회
    public List<FileRecodingDTO> selectByMeetingAndMemberId(@Param("opponentId") Long opponentId,
                                                            @Param("memberId") Long memberId);

    // 회의 id로 녹음 파일 조회
    public FileRecodingDTO selectByMeetingId(Long meetingId);
}
