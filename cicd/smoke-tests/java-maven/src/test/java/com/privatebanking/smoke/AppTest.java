package com.privatebanking.smoke;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class AppTest {
    @Test
    void portfolioValueAddsCashAndSecurities() {
        assertEquals(150, App.portfolioValue(100, 50));
    }
}
