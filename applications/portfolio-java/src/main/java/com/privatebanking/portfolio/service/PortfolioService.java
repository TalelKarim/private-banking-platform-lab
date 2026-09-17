package com.privatebanking.portfolio.service;

import com.privatebanking.portfolio.dto.PortfolioDto;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class PortfolioService {

    public List<PortfolioDto> findAll() {
        return List.of(
                new PortfolioDto(1L, "Client A", "Conservative Mandate", 150000.0, "EUR"),
                new PortfolioDto(2L, "Client B", "Balanced Mandate", 320000.0, "EUR"),
                new PortfolioDto(3L, "Client C", "Growth Mandate", 780000.0, "USD")
        );
    }

    public PortfolioDto findById(Long id) {
        return findAll()
                .stream()
                .filter(portfolio -> portfolio.id().equals(id))
                .findFirst()
                .orElseThrow(() -> new RuntimeException("Portfolio not found with id: " + id));
    }
}
