package com.app.globalgates.dto;

import lombok.Data;

@Data
public class AiAdResponse {
    private float predicted_budget;
    private float predicted_impression;
    private float predicted_min;
    private float predicted_max;
}
