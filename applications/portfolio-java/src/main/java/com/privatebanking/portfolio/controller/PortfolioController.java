package com.privatebanking.portfolio.controller;

import com.privatebanking.portfolio.dto.PortfolioDto;
import com.privatebanking.portfolio.service.PortfolioService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
public class PortfolioController {

    private final PortfolioService portfolioService;

    public PortfolioController(PortfolioService portfolioService) {
        this.portfolioService = portfolioService;
    }

    @GetMapping("/portfolios")
    public List<PortfolioDto> getPortfolios() {
        return portfolioService.findAll();
    }

    @GetMapping("/portfolios/{id}")
    public PortfolioDto getPortfolioById(@PathVariable Long id) {
        return portfolioService.findById(id);
    }
}
