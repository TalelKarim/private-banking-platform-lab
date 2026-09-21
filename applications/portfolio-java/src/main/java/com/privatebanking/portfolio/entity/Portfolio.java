package com.privatebanking.portfolio.entity;

import java.math.BigDecimal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "portfolios")
public class Portfolio {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "client_name", nullable = false)
    private String clientName;

    @Column(name = "portfolio_name", nullable = false)
    private String portfolioName;

    @Column(name = "total_value", nullable = false, precision = 18, scale = 2)
    private BigDecimal totalValue;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency;

    protected Portfolio() {
        // Constructeur vide obligatoire pour JPA/Hibernate
    }

    public Portfolio(String clientName, String portfolioName, BigDecimal totalValue, String currency) {
        this.clientName = clientName;
        this.portfolioName = portfolioName;
        this.totalValue = totalValue;
        this.currency = currency;
    }


    public void update(
            String clientName,
            String portfolioName,
            BigDecimal totalValue,
            String currency
    ) {
        this.clientName = clientName;
        this.portfolioName = portfolioName;
        this.totalValue = totalValue;
        this.currency = currency;
    }
    
    public Long getId() {
        return id;
    }

    public String getClientName() {
        return clientName;
    }

    public String getPortfolioName() {
        return portfolioName;
    }

    public BigDecimal getTotalValue() {
        return totalValue;
    }

    public String getCurrency() {
        return currency;
    }
}
