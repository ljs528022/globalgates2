package com.app.globalgates.domain.video_chat;

import lombok.*;

@Getter
@ToString
@EqualsAndHashCode(of = "id")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PROTECTED)
@Builder
public class SummationVO {
    public Long id;
    public Long record_id;
    public String text;
}
