package com.privatebanking.portfolio.dto;

public record PortfolioDto(
        Long id,
        String clientName,
        String portfolioName,
        Double totalValue,
        String currency
) {
}
