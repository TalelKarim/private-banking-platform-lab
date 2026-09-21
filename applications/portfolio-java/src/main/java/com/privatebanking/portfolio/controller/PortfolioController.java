package com.privatebanking.portfolio.controller;

import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.privatebanking.portfolio.dto.PortfolioDto;
import com.privatebanking.portfolio.dto.PortfolioRequest;
import com.privatebanking.portfolio.service.PortfolioService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/portfolios")
public class PortfolioController {

    private static final Logger log =
            LoggerFactory.getLogger(PortfolioController.class);

    private final PortfolioService portfolioService;

    public PortfolioController(PortfolioService portfolioService) {
        this.portfolioService = portfolioService;
    }

    @GetMapping
    public List<PortfolioDto> getPortfolios() {

        log.info("HTTP GET /portfolios");

        return portfolioService.findAll();
    }

    @GetMapping("/{id}")
    public PortfolioDto getPortfolioById(@PathVariable Long id) {

        log.info("HTTP GET /portfolios/{}", id);

        return portfolioService.findById(id);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public PortfolioDto createPortfolio(
            @Valid @RequestBody PortfolioRequest request
    ) {

        log.info("HTTP POST /portfolios");

        return portfolioService.create(request);
    }

    @PutMapping("/{id}")
    public PortfolioDto updatePortfolio(
            @PathVariable Long id,
            @Valid @RequestBody PortfolioRequest request
    ) {

        log.info("HTTP PUT /portfolios/{}", id);

        return portfolioService.update(id, request);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deletePortfolio(@PathVariable Long id) {

        log.info("HTTP DELETE /portfolios/{}", id);

        portfolioService.delete(id);
    }
}