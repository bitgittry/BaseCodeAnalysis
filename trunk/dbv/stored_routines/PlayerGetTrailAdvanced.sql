DROP procedure IF EXISTS `PlayerGetTrailAdvanced`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGetTrailAdvanced`(clientStatID BIGINT, dateFrom DATETIME, dateTo DATETIME, perPage INT, pageNo INT)
BEGIN
  
  -- !! This was to be able to do multilingual
  -- optimized (actually no one is using this but instead they use  PlayerGetTrail)
  
  
  DECLARE firstResult, countPlus1 INT DEFAULT 0;

  SET @client_stat_id=clientStatID;
  SET @date_from=dateFrom;
  SET @date_to=dateTo;
  
  SET @perPage=perPage; 
  SET @pageNo=pageNo;
  SET @firstResult=(@pageNo-1)*@perPage; 
 
  SET @a=@firstResult+1;
  SET @b=@firstResult+@perPage;
  SET @n=0;
  
  SET firstResult=@a-1;
  SET countPlus1=firstResult+perPage+1;

  SET @convertDivide=100;
  SET @currencySymbol='';
  
  SELECT gaming_currency.symbol INTO @currencySymbol FROM gaming_currency JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gaming_currency.currency_id=gaming_client_stats.currency_id;
  -- SELECT IF(value_bool,100,1) INTO @convertExtenal FROM gaming_settings WHERE name='PORTAL_CONVERTION_USE_EXTERNAL_FORMAT';
  
  SELECT COUNT(*) AS num_transactions
  FROM gaming_game_plays FORCE INDEX (player_date)
  JOIN gaming_payment_transaction_type ON 
    gaming_game_plays.client_stat_id=@client_stat_id AND (gaming_game_plays.timestamp BETWEEN @date_from AND @date_to) AND
    gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id;
  
    SELECT 
      game_play_id AS trail_id,
      gaming_game_plays.timestamp AS `timestamp`,
      IF(gaming_games.game_id IS NULL OR gaming_payment_transaction_type.is_common_wallet_adjustment_type, 
         IF(gaming_game_plays.sb_extra_id IS NOT NULL, CONCAT(IF(play_messages.tran_selector='s', 
            CONCAT(IFNULL(CONCAT(gaming_sb_events.name, ' - ', gaming_sb_markets.name, ' - '),'Sport - '), gaming_sb_selections.name), 
            CONCAT(IFNULL(gaming_sb_multiple_types.name,'Multiple'))),' - ', IF (gaming_payment_transaction_type.name='WIN' AND amount_total = 0, 
            CONCAT('Loses - ',ROUND(ABS(bet_total)/@convertDivide,2)),  CONCAT('Win - ',ROUND(ABS(win_total-bet_total)/@convertDivide,2))
         )),
        CONCAT(gaming_payment_transaction_type.display_name)), -- ,' - ',@currencySymbol,amount_total/@convertDivide
        CONCAT(gaming_games.game_description,' - ',play_messages.message,' - ',
          CASE play_messages.name
            WHEN 'HandWins' THEN CONCAT(IF(jackpot_win>0,CONCAT('Jackpot Win ',@currencySymbol,ROUND(jackpot_win/@convertDivide,2),' - '),''), 'Win ', @currencySymbol, ROUND((win_total-jackpot_win-bet_total)/@convertDivide,2),' - ','Bet ',@currencySymbol, ROUND(bet_total/@convertDivide,2))
            WHEN 'HandLoses' THEN CONCAT(IF(jackpot_win>0,CONCAT('Jackpot Win ',@currencySymbol,ROUND(jackpot_win/@convertDivide,2),' - '),''), 'Loses ', @currencySymbol, ROUND((bet_total-jackpot_win-win_total)/@convertDivide,2),' - ','Bet ',@currencySymbol, ROUND(bet_total/@convertDivide,2))
            ELSE CONCAT(@currencySymbol, ROUND(ABS(amount_total)/@convertDivide,2))
          END,
      IF (gaming_game_round_types.name IS NULL OR gaming_game_round_types.selector='N','',CONCAT(' (', gaming_game_round_types.name,')')))) AS `description`,
      IF(amount_real*gaming_game_plays.sign_mult > 0, amount_real, NULL) AS `credit_real`,
      ABS(IF(amount_real*gaming_game_plays.sign_mult < 0, amount_real, NULL)) AS `debit_real`,
      IF((amount_bonus+amount_bonus_win_locked)*gaming_game_plays.sign_mult > 0, ROUND(amount_bonus+amount_bonus_win_locked, 2), NULL) AS `credit_bonus`,
      ABS(IF((amount_bonus+amount_bonus_win_locked)*gaming_game_plays.sign_mult < 0, ROUND(amount_bonus+amount_bonus_win_locked, 2), NULL)) AS `debit_bonus`,
      gaming_game_plays.balance_real_after AS `balance_real`, gaming_game_plays.balance_bonus_after AS `balance_bonus`,
      gaming_game_plays.pending_bet_real, gaming_game_plays.pending_bet_bonus,
      gaming_game_plays.game_round_id AS `game_round_id`, gaming_games.game_id, 
      IF(gaming_payment_transaction_type.name='Win' AND bet_total>win_total, 'Loss', gaming_payment_transaction_type.name) AS transaction_type, gaming_license_type.name AS license_type,
      amount_total, bet_total, IF(play_messages.is_round_finished, win_total, NULL) AS win_total, IF(play_messages.is_round_finished OR play_messages.name='PJWin', jackpot_win, NULL) AS jackpot_win, play_messages.name AS play_message_type,
	  gaming_game_plays.loyalty_points, gaming_game_plays.loyalty_points_bonus
    FROM gaming_game_plays FORCE INDEX (player_date)
    JOIN gaming_payment_transaction_type ON 
      gaming_game_plays.client_stat_id=@client_stat_id AND (gaming_game_plays.timestamp BETWEEN @date_from AND @date_to) AND
      gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
    JOIN gaming_license_type ON gaming_game_plays.license_type_id = gaming_license_type.license_type_id
    LEFT JOIN gaming_games ON gaming_game_plays.game_id=gaming_games.game_id
    LEFT JOIN gaming_game_play_message_types AS play_messages ON gaming_game_plays.game_play_message_type_id=play_messages.game_play_message_type_id
    LEFT JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
    LEFT JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id
    LEFT JOIN gaming_sb_selections ON play_messages.tran_selector='s' AND gaming_game_plays.sb_extra_id=gaming_sb_selections.sb_selection_id
    LEFT JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    LEFT JOIN gaming_sb_events ON gaming_sb_markets.sb_event_id = gaming_sb_events.sb_event_id
    LEFT JOIN gaming_sb_multiple_types ON play_messages.tran_selector='sm' AND gaming_game_plays.sb_extra_id=gaming_sb_multiple_types.sb_multiple_type_id
    ORDER BY gaming_game_plays.timestamp DESC, gaming_game_plays.game_play_id DESC 
	LIMIT firstResult, perPage;
END$$

DELIMITER ;

