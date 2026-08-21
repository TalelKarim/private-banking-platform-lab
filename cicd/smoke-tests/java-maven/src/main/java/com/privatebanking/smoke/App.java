package com.privatebanking.smoke;

public final class App {
    private App() {
    }

    public static int portfolioValue(int cash, int securities) {
        return cash + securities;
    }

    public static void main(String[] args) {
        System.out.println("portfolio-java-smoke=" + portfolioValue(100, 50));
    }
}
