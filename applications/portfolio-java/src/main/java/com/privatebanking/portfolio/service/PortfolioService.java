package com.privatebanking.portfolio.service;

import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import com.privatebanking.portfolio.dto.PortfolioDto;
import com.privatebanking.portfolio.dto.PortfolioRequest;
import com.privatebanking.portfolio.entity.Portfolio;
import com.privatebanking.portfolio.repository.PortfolioRepository;

@Service
public class PortfolioService {

    private static final Logger log =
            LoggerFactory.getLogger(PortfolioService.class);

    private final PortfolioRepository portfolioRepository;

    public PortfolioService(PortfolioRepository portfolioRepository) {
        this.portfolioRepository = portfolioRepository;
    }

    public List<PortfolioDto> findAll() {

        log.debug("Loading all portfolios from database");

        List<PortfolioDto> portfolios =
                portfolioRepository.findAll()
                        .stream()
                        .map(this::toDto)
                        .toList();

        log.info("Loaded {} portfolios", portfolios.size());

        return portfolios;
    }


    public PortfolioDto create(PortfolioRequest request) {

        log.info(
                "Creating portfolio for clientName={} currency={}",
                request.clientName(),
                request.currency()
        );

        Portfolio portfolio = new Portfolio(
                request.clientName(),
                request.portfolioName(),
                request.totalValue(),
                request.currency()
        );

        Portfolio savedPortfolio = portfolioRepository.save(portfolio);

        log.info("Portfolio created id={}", savedPortfolio.getId());

        return toDto(savedPortfolio);
    }



    public PortfolioDto update(Long id, PortfolioRequest request) {

        log.info("Updating portfolio id={}", id);

        Portfolio portfolio = portfolioRepository.findById(id)
                .orElseThrow(() -> {
                    log.warn("Portfolio not found for update id={}", id);

                    return new ResponseStatusException(
                            HttpStatus.NOT_FOUND,
                            "Portfolio not found with id: " + id
                    );
                });

        portfolio.update(
                request.clientName(),
                request.portfolioName(),
                request.totalValue(),
                request.currency()
        );

        Portfolio savedPortfolio = portfolioRepository.save(portfolio);

        log.info("Portfolio updated id={}", id);

        return toDto(savedPortfolio);
}




    public void delete(Long id) {

        log.info("Deleting portfolio id={}", id);

        if (!portfolioRepository.existsById(id)) {

            log.warn("Portfolio not found for deletion id={}", id);

            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND,
                    "Portfolio not found with id: " + id
            );
        }

        portfolioRepository.deleteById(id);

        log.info("Portfolio deleted id={}", id);
    }

    public PortfolioDto findById(Long id) {

        log.debug("Searching portfolio id={}", id);

        return portfolioRepository.findById(id)
                .map(portfolio -> {
                    log.info("Portfolio found id={}", id);
                    return toDto(portfolio);
                })
                .orElseThrow(() -> {
                    log.warn("Portfolio not found id={}", id);

                    return new ResponseStatusException(
                            HttpStatus.NOT_FOUND,
                            "Portfolio not found with id: " + id
                    );
                });
    }

    private PortfolioDto toDto(Portfolio portfolio) {

        return new PortfolioDto(
                portfolio.getId(),
                portfolio.getClientName(),
                portfolio.getPortfolioName(),
                portfolio.getTotalValue(),
                portfolio.getCurrency()
        );
    }
}