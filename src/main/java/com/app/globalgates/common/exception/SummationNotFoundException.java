package com.app.globalgates.common.exception;

public class SummationNotFoundException extends RuntimeException {
    public SummationNotFoundException() {}

    public SummationNotFoundException(String message) {
        super(message);
    }
}
