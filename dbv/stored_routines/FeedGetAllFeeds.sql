DROP procedure IF EXISTS `FeedGetAllFeeds`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FeedGetAllFeeds`(clientStatID BIGINT, includeTestPlayers TINYINT(1))
root: BEGIN

	-- 
 	DECLARE exchangeRate DECIMAL(18,5) DEFAULT 1.0;
	DECLARE operatorID BIGINT DEFAULT 3;

	IF (clientStatID!=0) THEN
		SELECT gaming_operator_currency.exchange_rate, gaming_operators.operator_id INTO exchangeRate, operatorID
		FROM gaming_client_stats 
		JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
		JOIN gaming_operators ON gaming_operator_currency.operator_id=gaming_operators.operator_id AND gaming_operators.is_main_operator=1
		WHERE gaming_client_stats.client_stat_id=clientStatID
		LIMIT 1;
	ELSE
		SET exchangeRate=1.0;
		SELECT operator_id INTO operatorID
		FROM gaming_operators 
		WHERE gaming_operators.is_main_operator=1
		LIMIT 1;
	END IF;

  -- Jackpot Feed
	SELECT gm_jackpots.game_manufacturer_jackpot_id, gm_jackpots.display_name AS jackot_title, gaming_currency.currency_code, gm_jackpots.current_value, 
		gaming_games.game_id, gaming_games.manufacturer_game_idf, gaming_game_manufacturers.name AS game_manufacturer_name
	FROM gaming_game_manufacturers_jackpots AS gm_jackpots FORCE INDEX (last_updated)
	JOIN gaming_game_manufacturers ON gaming_game_manufacturers.is_active=1 AND gm_jackpots.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id 
	JOIN gaming_currency ON gm_jackpots.is_active AND gm_jackpots.currency_id=gaming_currency.currency_id
	JOIN gaming_game_manufacturers_jackpots_games AS gm_jackpots_games ON gm_jackpots.is_active=1 AND gm_jackpots.game_manufacturer_jackpot_id=gm_jackpots_games.game_manufacturer_jackpot_id
	JOIN gaming_games ON gm_jackpots_games.game_id=gaming_games.game_id
	WHERE gm_jackpots.is_active
	ORDER BY gm_jackpots.last_updated DESC LIMIT 100;

  -- Registered Players
	SELECT gaming_clients.sign_up_date, 
		gaming_platform_types.platform_type, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.name AS first_name, gaming_clients.nickname, gaming_clients.sign_up_date, gaming_clients.gender, 
		gaming_countries.country_code, gaming_countries.name AS country_name, clients_locations.city, gaming_languages.language_code, gaming_clients.vip_level, gaming_clients.vip_level_id, gaming_affiliates.affiliate_code
	FROM gaming_clients FORCE INDEX (sign_up_date)
	JOIN gaming_client_stats ON gaming_clients.client_id=gaming_client_stats.client_stat_id AND gaming_client_stats.is_active       
    LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
	LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id
	LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
	LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
    LEFT JOIN gaming_platform_types ON gaming_clients.platform_type_id=gaming_platform_types.platform_type_id
    WHERE gaming_clients.news_feeds_allow AND (includeTestPlayers=1 OR gaming_clients.is_test_player=0) AND is_account_closed = 0
	ORDER BY gaming_clients.sign_up_date DESC LIMIT 40;

  -- Logged In Players
	SELECT gclat.last_success AS date_open, gaming_client_sessions.total_bet_base, gaming_client_sessions.total_win_base, 
	   ROUND(gaming_client_sessions.total_bet_base*exchangeRate, 0) AS total_bet_c, ROUND(gaming_client_sessions.total_win_base*exchangeRate, 0) AS total_win_c,
	   gaming_platform_types.platform_type, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.name AS first_name, gaming_clients.nickname, gaming_clients.sign_up_date, gaming_clients.gender, 
	   gaming_countries.country_code, gaming_countries.name AS country_name, clients_locations.city, gaming_languages.language_code, gaming_clients.vip_level, gaming_clients.vip_level_id, gaming_affiliates.affiliate_code 
	FROM gaming_clients_login_attempts_totals AS gclat FORCE INDEX (last_success) 
	JOIN sessions_main FORCE INDEX (client_latest_session) ON gclat.client_id=sessions_main.extra_id AND sessions_main.is_latest
	JOIN gaming_client_sessions ON sessions_main.session_id=gaming_client_sessions.session_id
	JOIN gaming_client_stats ON sessions_main.extra2_id=gaming_client_stats.client_stat_id       
	JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
	LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
	LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id	
	LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
	LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
    LEFT JOIN gaming_platform_types ON sessions_main.platform_type_id=gaming_platform_types.platform_type_id
    WHERE gaming_clients.news_feeds_allow AND (includeTestPlayers=1 OR gaming_clients.is_test_player=0) AND is_account_closed = 0
	ORDER BY gclat.last_success DESC LIMIT 40;

  -- Game Win
	SELECT gaming_games.game_id, gaming_games.manufacturer_game_idf, gaming_game_rounds.date_time_start AS round_time, gaming_game_rounds.bet_total_base, gaming_game_rounds.win_total_base, 
	  ROUND(gaming_game_rounds.bet_total_base*exchangeRate, 0) AS bet_total_c, ROUND(gaming_game_rounds.win_total_base*exchangeRate, 0) AS win_total_c, 
	  IFNULL(gaming_platform_types.platform_type, gaming_platform_types2.platform_type) AS platform_type, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.name AS first_name, gaming_clients.nickname, gaming_clients.sign_up_date, gaming_clients.gender, 
	  gaming_countries.country_code, gaming_countries.name AS country_name, clients_locations.city, gaming_languages.language_code, gaming_clients.vip_level, gaming_clients.vip_level_id, gaming_affiliates.affiliate_code 
	FROM gaming_game_rounds FORCE INDEX (date_time_end)
	JOIN gaming_game_plays ON gaming_game_rounds.game_round_id=gaming_game_plays.game_round_id AND gaming_game_plays.round_transaction_no=1
	JOIN gaming_games ON gaming_game_rounds.game_id=gaming_games.game_id
	JOIN gaming_client_stats ON gaming_game_rounds.client_stat_id=gaming_client_stats.client_stat_id       
	JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
	LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
	LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id	
	LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
	LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
    LEFT JOIN gaming_platform_types ON gaming_game_plays.platform_type_id=gaming_platform_types.platform_type_id
	LEFT JOIN sessions_main ON gaming_game_plays.session_id=sessions_main.session_id -- if platfrom type of bet is null return platform of session
	LEFT JOIN gaming_platform_types AS gaming_platform_types2 ON sessions_main.platform_type_id=gaming_platform_types2.platform_type_id
	WHERE gaming_game_rounds.win_total_base>gaming_game_rounds.bet_total_base 
		AND gaming_clients.news_feeds_allow AND (includeTestPlayers=1 OR gaming_clients.is_test_player=0) AND is_account_closed = 0
	ORDER BY gaming_game_rounds.date_time_end DESC LIMIT 40;

  -- Bonus Awarded
	SELECT gaming_bonus_instances.given_date, gaming_bonus_instances.bonus_rule_id, gaming_bonus_instances.bonus_amount_given, ROUND((gaming_bonus_instances.bonus_amount_given/opp_currency.exchange_rate)*exchangeRate, 0) AS bonus_amount_given_c,
	  gaming_platform_types.platform_type, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.name AS first_name, gaming_clients.nickname, gaming_clients.sign_up_date, gaming_clients.gender, 
	  gaming_countries.country_code, gaming_countries.name AS country_name, clients_locations.city, gaming_languages.language_code, gaming_clients.vip_level, gaming_clients.vip_level_id, gaming_affiliates.affiliate_code  
	FROM gaming_bonus_instances FORCE INDEX  (given_date)
	JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id
	JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
	JOIN gaming_operator_currency AS opp_currency ON gaming_client_stats.currency_id=opp_currency.currency_id AND opp_currency.operator_id=operatorID
	LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
	LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id
	LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
	LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
    LEFT JOIN sessions_main ON gaming_bonus_instances.session_id=sessions_main.session_id
	LEFT JOIN gaming_platform_types ON sessions_main.platform_type_id=gaming_platform_types.platform_type_id
	WHERE gaming_clients.news_feeds_allow AND (includeTestPlayers=1 OR gaming_clients.is_test_player=0) AND is_account_closed = 0
	ORDER BY gaming_bonus_instances.given_date DESC LIMIT 40;

  -- Bonus Secured
	SELECT gaming_bonus_instances.secured_date, gaming_bonus_instances.bonus_rule_id, gaming_bonus_instances.bonus_transfered_total, ROUND((gaming_bonus_instances.bonus_transfered_total/opp_currency.exchange_rate)*exchangeRate, 0) AS bonus_transfered_total_c,
	  gaming_platform_types.platform_type, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.name AS first_name, gaming_clients.nickname, gaming_clients.sign_up_date, gaming_clients.gender, 
      gaming_countries.country_code, gaming_countries.name AS country_name, clients_locations.city, gaming_languages.language_code, gaming_clients.vip_level, gaming_clients.vip_level_id, gaming_affiliates.affiliate_code  
	FROM gaming_bonus_instances FORCE INDEX (secured_date)
	JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id
	JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
	JOIN gaming_operator_currency AS opp_currency ON gaming_client_stats.currency_id=opp_currency.currency_id AND opp_currency.operator_id=operatorID
    LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
	LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id
    LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
	LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
    LEFT JOIN sessions_main ON gaming_bonus_instances.session_id=sessions_main.session_id
	LEFT JOIN gaming_platform_types ON sessions_main.platform_type_id=gaming_platform_types.platform_type_id
	WHERE gaming_bonus_instances.secured_date IS NOT NULL AND gaming_clients.news_feeds_allow AND (includeTestPlayers=1 OR gaming_clients.is_test_player=0) AND is_account_closed = 0
	ORDER BY gaming_bonus_instances.secured_date DESC LIMIT 40;

  -- Promotion Completed
  	SELECT promotion_statuses.promotion_id, promotion_statuses.requirement_achieved_date, promotion_statuses.num_rounds,
	  gaming_platform_types.platform_type, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.name AS first_name, gaming_clients.nickname, gaming_clients.sign_up_date, gaming_clients.gender, 
      gaming_countries.country_code, gaming_countries.name AS country_name, clients_locations.city, gaming_languages.language_code, gaming_clients.vip_level, gaming_clients.vip_level_id, gaming_affiliates.affiliate_code  
	FROM gaming_promotions_player_statuses AS promotion_statuses FORCE INDEX (requirement_achieved_date)
	JOIN gaming_client_stats ON promotion_statuses.client_stat_id=gaming_client_stats.client_stat_id
	JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
	LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
	LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id
	LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
	LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
    LEFT JOIN sessions_main ON promotion_statuses.session_id=sessions_main.session_id
	LEFT JOIN gaming_platform_types ON sessions_main.platform_type_id=gaming_platform_types.platform_type_id
	WHERE promotion_statuses.requirement_achieved_date IS NOT NULL AND gaming_clients.news_feeds_allow AND (includeTestPlayers=1 OR gaming_clients.is_test_player=0) AND is_account_closed = 0
	ORDER BY promotion_statuses.requirement_achieved_date DESC LIMIT 40;

  -- Loyalty Redeemed Prize
	SELECT glrt.loyalty_redemption_id, glrpt.prize_type, glrt.extra_id, glrt.loyalty_points, glrt.amount, ROUND((glrt.amount/opp_currency.exchange_rate)*exchangeRate, 0) AS amount_c, glrt.free_rounds, glrt.transaction_date,
		gaming_platform_types.platform_type, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.name AS first_name, gaming_clients.nickname, gaming_clients.sign_up_date, gaming_clients.gender, 
        gaming_countries.country_code, gaming_countries.name AS country_name, clients_locations.city, gaming_languages.language_code, gaming_clients.vip_level, gaming_clients.vip_level_id, gaming_affiliates.affiliate_code  
	FROM gaming_loyalty_redemption_transactions AS glrt FORCE INDEX (transaction_date)
	JOIN gaming_loyalty_redemption_prize_types AS glrpt ON glrt.loyalty_redemption_prize_type_id=glrpt.loyalty_redemption_prize_type_id
	JOIN gaming_client_stats ON glrt.client_stat_id=gaming_client_stats.client_stat_id
	JOIN gaming_operator_currency AS opp_currency ON gaming_client_stats.currency_id=opp_currency.currency_id AND opp_currency.operator_id=operatorID
	JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
	LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
	LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id
	LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
	LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
	LEFT JOIN sessions_main ON glrt.session_id=sessions_main.session_id
	LEFT JOIN gaming_platform_types ON sessions_main.platform_type_id=gaming_platform_types.platform_type_id
	WHERE gaming_clients.news_feeds_allow AND (includeTestPlayers=1 OR gaming_clients.is_test_player=0) AND is_account_closed = 0
	ORDER BY glrt.transaction_date DESC LIMIT 40; 

  -- Games Launched
	SELECT gaming_games.game_id, gaming_games.manufacturer_game_idf, gaming_game_sessions.session_start_date, gaming_game_sessions.total_bet_base, gaming_game_sessions.total_win_base, 
	  ROUND(gaming_game_sessions.total_bet_base*exchangeRate, 0) AS total_bet_c, ROUND(gaming_game_sessions.total_win_base*exchangeRate, 0) AS total_win_c, 
	  gaming_platform_types.platform_type, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.name AS first_name, gaming_clients.nickname, gaming_clients.sign_up_date, gaming_clients.gender, 
	  gaming_countries.country_code, gaming_countries.name AS country_name, clients_locations.city, gaming_languages.language_code, gaming_clients.vip_level, gaming_clients.vip_level_id, gaming_affiliates.affiliate_code  
	FROM gaming_game_sessions FORCE INDEX (session_start_date)
	JOIN sessions_main ON gaming_game_sessions.session_id=sessions_main.session_id
	JOIN gaming_games ON gaming_game_sessions.game_id=gaming_games.game_id
	JOIN gaming_client_stats ON gaming_game_sessions.client_stat_id=gaming_client_stats.client_stat_id       
	JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
	LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
	LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id	
	LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
	LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
	LEFT JOIN gaming_platform_types ON sessions_main.platform_type_id=gaming_platform_types.platform_type_id
	WHERE gaming_clients.news_feeds_allow AND (includeTestPlayers=1 OR gaming_clients.is_test_player=0) AND is_account_closed = 0
	ORDER BY gaming_game_sessions.session_start_date DESC LIMIT 40;
 
  -- Transaction Deposit
	SELECT gaming_balance_history.timestamp, gaming_balance_history.amount_base, ROUND(gaming_balance_history.amount_base*exchangeRate, 0) AS amount_c, gaming_payment_method.display_name AS payment_method,
	  gaming_platform_types.platform_type, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.name AS first_name, gaming_clients.nickname, gaming_clients.sign_up_date, gaming_clients.gender, 
	  gaming_countries.country_code, gaming_countries.name AS country_name, clients_locations.city, gaming_languages.language_code, gaming_clients.vip_level, gaming_clients.vip_level_id, gaming_affiliates.affiliate_code  
	FROM gaming_client_stats
	JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'
	JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name IN ('Accepted','Authorized_Pending')
	JOIN gaming_balance_history FORCE INDEX (timestamp) ON
	  gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
	  gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id AND
	  gaming_balance_history.client_stat_id = gaming_client_stats.client_stat_id 
	JOIN gaming_payment_method ON gaming_balance_history.sub_payment_method_id=gaming_payment_method.payment_method_id
	JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id 
	LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
	LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id	
	LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
	LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
	LEFT JOIN gaming_platform_types ON gaming_balance_history.platform_type_id=gaming_platform_types.platform_type_id
	WHERE gaming_clients.news_feeds_allow AND (includeTestPlayers=1 OR gaming_clients.is_test_player=0) AND is_account_closed = 0
	ORDER BY gaming_balance_history.timestamp DESC LIMIT 40;

  -- Transaction Withdrawal Requests
	SELECT withdrawal_requests.request_datetime, withdrawal_requests.amount_base, ROUND(withdrawal_requests.amount_base*exchangeRate, 0) AS amount_c, gaming_payment_method.display_name AS payment_method, 
		gaming_platform_types.platform_type, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.name AS first_name, gaming_clients.nickname, gaming_clients.sign_up_date, gaming_clients.gender, 
		gaming_countries.country_code, gaming_countries.name AS country_name, clients_locations.city, gaming_languages.language_code, gaming_clients.vip_level, gaming_clients.vip_level_id, gaming_affiliates.affiliate_code  
	FROM gaming_balance_withdrawal_requests AS withdrawal_requests  FORCE INDEX (request_datetime)
	JOIN gaming_balance_history ON withdrawal_requests.balance_history_id=gaming_balance_history.balance_history_id
	JOIN gaming_payment_method ON gaming_balance_history.payment_method_id=gaming_payment_method.payment_method_id
	JOIN gaming_client_stats ON withdrawal_requests.client_stat_id=gaming_client_stats.client_stat_id       
	JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
	LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
	LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id	
	LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
	LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
	LEFT JOIN gaming_platform_types ON gaming_balance_history.platform_type_id=gaming_platform_types.platform_type_id
	WHERE gaming_clients.news_feeds_allow AND (includeTestPlayers=1 OR gaming_clients.is_test_player=0) AND is_account_closed = 0
	ORDER BY withdrawal_requests.request_datetime DESC LIMIT 40;

END root$$

DELIMITER ;

