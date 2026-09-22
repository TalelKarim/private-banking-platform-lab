INSERT INTO portfolios (client_name, portfolio_name, total_value, currency)
SELECT 'Client A', 'Conservative Mandate', 150000.00, 'EUR'
WHERE NOT EXISTS (SELECT 1 FROM portfolios WHERE client_name = 'Client A' AND portfolio_name = 'Conservative Mandate');

INSERT INTO portfolios (client_name, portfolio_name, total_value, currency)
SELECT 'Client B', 'Balanced Mandate', 320000.00, 'EUR'
WHERE NOT EXISTS (SELECT 1 FROM portfolios WHERE client_name = 'Client B' AND portfolio_name = 'Balanced Mandate');

INSERT INTO portfolios (client_name, portfolio_name, total_value, currency)
SELECT 'Client C', 'Growth Mandate', 780000.00, 'USD'
WHERE NOT EXISTS (SELECT 1 FROM portfolios WHERE client_name = 'Client C' AND portfolio_name = 'Growth Mandate');
