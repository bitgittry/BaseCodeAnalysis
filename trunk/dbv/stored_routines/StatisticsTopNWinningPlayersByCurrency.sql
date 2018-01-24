DROP procedure IF EXISTS `StatisticsTopNWinningPlayersByCurrency`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `StatisticsTopNWinningPlayersByCurrency`(minuteInterval INT, limitRows INT, currencyCode VARCHAR(5))
BEGIN
  
  DECLARE currencyCodeCheck VARCHAR(3) DEFAULT 'EUR';
  DECLARE exchangeRate DECIMAL(18, 5) DEFAULT 1;
  DECLARE currencyIDCheck BIGINT DEFAULT -1;
  
  SELECT gaming_operator_currency.currency_id, currency_code, exchange_rate INTO currencyIDCheck, currencyCodeCheck, exchangeRate  
  FROM gaming_operators 
  JOIN gaming_currency ON gaming_operators.is_main_operator AND gaming_currency.currency_code=currencyCode
  JOIN gaming_operator_currency ON gaming_operator_currency.operator_id=gaming_operators.operator_id AND
    gaming_operator_currency.currency_id=gaming_currency.currency_id;
  
  SET @dateFrom = SUBDATE(NOW(), INTERVAL minuteInterval MINUTE);
  SET @dateTo = NOW();
  SET @rowNum=0;
  SELECT row_num, nickname, currency_code, country_code, win_total
  FROM
  (
    SELECT @rowNum:=@rowNum+1 AS row_num, gaming_clients.nickname, currencyCode AS currency_code, gaming_countries.country_code AS country_code, ROUND(GG.win_total_base*exchangeRate,0) AS win_total 
    FROM gaming_client_stats 
    JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active AND gaming_clients.is_test_player=0
    LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id 
    JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id  
    JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id  
    JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
    JOIN
    (
      SELECT gaming_client_sessions.client_stat_id, ROUND(total_win-total_bet,0) AS win_total, ROUND(total_win_base-total_bet_base,0) AS win_total_base 
      FROM sessions_main
      JOIN gaming_client_sessions ON sessions_main.date_closed BETWEEN @dateFrom AND @dateTo AND sessions_main.session_id=gaming_client_sessions.session_id AND ((total_win-total_bet)>=1000)
      ORDER BY sessions_main.date_closed DESC
    ) AS GG ON gaming_client_stats.client_stat_id=GG.client_stat_id 
    WHERE gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL)
    GROUP BY gaming_client_stats.client_stat_id
    
    
  ) AS GG
  WHERE row_num <= limitRows 
  ORDER BY row_num;
  
  
  
END$$

DELIMITER ;

