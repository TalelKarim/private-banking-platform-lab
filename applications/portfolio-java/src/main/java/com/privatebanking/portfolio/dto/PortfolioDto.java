package com.privatebanking.portfolio.dto;

import java.math.BigDecimal;

public record PortfolioDto(
        Long id,
        String clientName,
        String portfolioName,
        BigDecimal totalValue,
        String currency
) {
}
