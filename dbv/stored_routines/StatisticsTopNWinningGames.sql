DROP procedure IF EXISTS `StatisticsTopNWinningGames`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `StatisticsTopNWinningGames`(minuteInterval INT, limitRows INT, currencyID BIGINT)
BEGIN
  
  DECLARE currencyCode VARCHAR(3) DEFAULT 'EUR';
  DECLARE exchangeRate DECIMAL(18, 5) DEFAULT 1;
  DECLARE currencyIDCheck BIGINT DEFAULT -1;
  
  SELECT gaming_operator_currency.currency_id, currency_code, exchange_rate INTO currencyIDCheck, currencyCode, exchangeRate  
  FROM gaming_operators 
  JOIN gaming_currency ON gaming_operators.is_main_operator AND gaming_currency.currency_id=currencyID
  JOIN gaming_operator_currency ON gaming_operator_currency.operator_id=gaming_operators.operator_id AND
    gaming_operator_currency.currency_id=gaming_currency.currency_id;
    
  
  SET @rowNum=0;
  SELECT row_num, game_id, game_name, game_description, win_total, currency_code
  FROM
  (
    SELECT @rowNum:=@rowNum+1 AS row_num, gaming_games.game_id, game_name, game_description, ROUND(GG.total_win_base*exchangeRate,0) AS win_total, currencyCode AS currency_code 
    FROM gaming_games  
    JOIN gaming_operator_games ON 
      gaming_games.is_launchable=1 AND
      gaming_games.game_id=gaming_operator_games.game_id
    JOIN 
    (
      SELECT operator_game_id, SUM(total_win_base) AS total_win_base 
      FROM gaming_game_sessions
      JOIN gaming_clients ON (gaming_clients.is_test_player=0)
      LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id 
      JOIN gaming_client_stats ON (gaming_game_sessions.client_stat_id=gaming_client_stats.client_stat_id AND gaming_clients.client_id = gaming_client_stats.client_id)
      WHERE gaming_game_sessions.session_start_date > SUBDATE(NOW(), INTERVAL minuteInterval MINUTE) AND (gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL))
      GROUP BY operator_game_id 
    ) AS GG ON gaming_operator_games.operator_game_id=GG.operator_game_id 
    WHERE GG.total_win_base > 0
    ORDER BY GG.total_win_base DESC
  ) AS GG
  WHERE row_num <= limitRows;
  
END$$

DELIMITER ;

