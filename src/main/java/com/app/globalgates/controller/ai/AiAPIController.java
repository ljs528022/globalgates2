package com.app.globalgates.controller.ai;

import com.app.globalgates.dto.AdvertisementDTO;
import com.app.globalgates.dto.AiAdResponse;
import com.app.globalgates.dto.AiPostResponse;
import com.app.globalgates.dto.video_chat.SummationRequest;
import com.app.globalgates.dto.video_chat.SummationResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;

import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.HashMap;
import java.util.Map;

@RestController
@Slf4j
@RequestMapping("/ai/**")
public class AiAPIController {
    private final WebClient webClient = WebClient.create("https://hints-alphabetical-inch-tab.trycloudflare.com");

    // 게시글 신뢰도 측정
    @PostMapping("post/trust")
    @ResponseBody
    public Mono<AiPostResponse> calcTrustScore(@RequestBody Map<String, String> request) {
        String text = request.get("text");
        log.info("받아온 문장: {}", text);

        return webClient.post()
                .uri("/api/ai/post")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(Map.of("text", text))
                .retrieve()
                .bodyToMono(AiPostResponse.class);
    }

    // 광고 예산 추천 시스템 (평균 예산, 최고/최저 예산값, 평균 노출 수)
    @PostMapping("ad/recommend")
    @ResponseBody
    public Flux<AiAdResponse> recommendBudget(@RequestBody AdvertisementDTO request) {

        return webClient.post()
                .uri("/api/ai/ad")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(request)
                .retrieve()
                .bodyToFlux(AiAdResponse.class);
    }

    // 녹화 파일 요약 요청
    @PostMapping("video-chat/summation")
    @ResponseBody
    public Mono<SummationResponse> summationRecord(@RequestBody SummationRequest request) {
        log.info("fileId: {}", request.getFileId());
        log.info("filePath: {}", request.getFilePath());

        Map<String, Object> body = new HashMap<>();
        body.put("file_id", request.getFileId());
        body.put("file_path", request.getFilePath());

        return webClient.post()
                .uri("/api/ai/summary")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(body)
                .retrieve()
                .bodyToMono(SummationResponse.class);
    }
}
