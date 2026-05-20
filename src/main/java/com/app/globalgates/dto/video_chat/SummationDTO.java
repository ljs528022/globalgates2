package com.app.globalgates.dto.video_chat;

import com.app.globalgates.domain.video_chat.SummationVO;
import lombok.*;

@Getter @Setter @ToString
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class SummationDTO {
    private Long id;
    private Long record_id;
    private String text;

    public SummationVO toVO() {
        return SummationVO.builder()
                .id(id)
                .record_id(record_id)
                .text(text)
                .build();
    }
}
