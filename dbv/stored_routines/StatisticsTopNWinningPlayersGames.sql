DROP procedure IF EXISTS `StatisticsTopNWinningPlayersGames`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `StatisticsTopNWinningPlayersGames`(minuteInterval INT, limitRows INT, currencyID BIGINT)
BEGIN
  
  SET @dateFrom = SUBDATE(NOW(), INTERVAL minuteInterval MINUTE);
  SET @dateTo = NOW();
  SET @rowNum=0;
  SELECT row_num, nickname, currency_code, country_code, game_id, game_title, win_total
  FROM
  (
    SELECT @rowNum:=@rowNum+1 AS row_num, GG.game_id, gaming_games.game_description AS game_title, gaming_clients.nickname, gaming_currency.currency_code, gaming_countries.country_code AS country_code, GG.win_total  
    FROM gaming_client_stats 
    JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active AND gaming_clients.is_test_player=0
    LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id 
    JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id  
    JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id  
    JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
    JOIN
    (
      
      SELECT gaming_game_sessions.client_stat_id, game_id, ROUND(total_win-total_bet,0) AS win_total, ROUND(total_win_base-total_bet_base,0) AS win_total_base 
      FROM gaming_game_sessions
      WHERE gaming_game_sessions.session_start_date BETWEEN @dateFrom AND @dateTo AND ((total_win-total_bet)>=1000)
      ORDER BY total_win-total_bet DESC
    ) AS GG ON gaming_client_stats.client_stat_id=GG.client_stat_id 
    JOIN gaming_games ON GG.game_id=gaming_games.game_id
    WHERE gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = 0)
    GROUP BY gaming_client_stats.client_stat_id
    
    
  ) AS GG
  WHERE row_num <= limitRows 
  ORDER BY row_num;
  
END$$

DELIMITER ;

