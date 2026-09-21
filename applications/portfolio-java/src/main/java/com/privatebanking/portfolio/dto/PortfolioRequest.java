package com.privatebanking.portfolio.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;

public record PortfolioRequest(

        @NotBlank(message = "clientName is required")
        String clientName,

        @NotBlank(message = "portfolioName is required")
        String portfolioName,

        @DecimalMin(value = "0.01", message = "totalValue must be greater than zero")
        BigDecimal totalValue,

        @NotBlank(message = "currency is required")
        @Size(min = 3, max = 3, message = "currency must contain exactly 3 characters")
        String currency
) {
}
