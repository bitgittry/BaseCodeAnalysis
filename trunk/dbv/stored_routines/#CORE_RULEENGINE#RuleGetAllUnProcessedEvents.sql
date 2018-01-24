DROP procedure IF EXISTS `RuleGetAllUnProcessedEvents`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleGetAllUnProcessedEvents`(ignoreSessionCheck TINYINT(1), OUT sessionsReturned INT)
root: BEGIN
  
  -- Updated registration events to check the player selection cache and if not found it is calculated on the fly.
  -- Fixed bug of session and game session check. Need only to update RULE_ENGINE_LAST_RUN_DATE when session data is returned
  -- Added GROUP BY gaming_events_instances.client_stat_id, gaming_events_instances.rule_event_id;  
  -- Super Optimized
  -- gaming_rules_instances.start_date optimization
  
  DECLARE ruleEngineEnabled TINYINT(1) DEFAULT 0;
  DECLARE lastRunDate DATETIME DEFAULT '2010-01-01';
  DECLARE dateNow DATETIME DEFAULT NOW();

  SELECT value_bool INTO ruleEngineEnabled FROM gaming_settings WHERE `name`='RULE_ENGINE_ENABLED';
  SELECT value_date INTO lastRunDate FROM gaming_settings WHERE `name`='RULE_ENGINE_LAST_RUN_DATE';

  IF (ruleEngineEnabled=0) THEN
	LEAVE root;
  END IF;

  UPDATE gaming_event_rows FORCE INDEX (rule_engine_state) SET rule_engine_state=2 WHERE rule_engine_state=0 LIMIT 5000;
 
  IF (ignoreSessionCheck=1 OR (DATE_SUB(NOW(), INTERVAL 1 MINUTE)>lastRunDate)) THEN

	  -- game sessions
	  SELECT gaming_game_sessions.game_session_id, gaming_game_sessions.game_id, gaming_game_sessions.session_start_date, gaming_game_sessions.client_stat_id,
		gaming_rules_events.rule_event_id, gaming_events.event_id, gaming_game_categories_games.game_category_id, 
        gaming_game_sessions.total_bet_real, gaming_game_sessions.total_bet_bonus, gaming_game_sessions.total_win_real, gaming_game_sessions.total_win_bonus, gaming_game_sessions.session_id,
		gaming_game_sessions.bets
	  FROM gaming_game_sessions FORCE INDEX (is_open)
	  STRAIGHT_JOIN gaming_operator_games ON gaming_game_sessions.operator_game_id=gaming_operator_games.operator_game_id
	  STRAIGHT_JOIN gaming_client_stats ON gaming_game_sessions.client_stat_id=gaming_client_stats.client_stat_id
	  STRAIGHT_JOIN gaming_game_categories_games ON gaming_game_sessions.game_id = gaming_game_categories_games.game_id
	  STRAIGHT_JOIN gaming_rules ON gaming_rules.is_active=1 
	  STRAIGHT_JOIN gaming_event_tables ON gaming_event_tables.table_name = 'gaming_game_sessions' 
      STRAIGHT_JOIN gaming_events ON gaming_events.event_table_id = gaming_event_tables.event_table_id 
      STRAIGHT_JOIN gaming_rules_events ON gaming_rules_events.rule_id=gaming_rules.rule_id AND gaming_rules_events.event_id=gaming_events.event_id
	  STRAIGHT_JOIN gaming_events_instances FORCE INDEX (player_rule_event) ON 
		(gaming_events_instances.client_stat_id = gaming_game_sessions.client_stat_id AND 
		gaming_rules_events.rule_event_id=gaming_events_instances.rule_event_id AND is_current=1 AND 
        gaming_events_instances.is_achieved=0 AND gaming_events_instances.has_failed=0)
	  STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_instances.rule_instance_id=gaming_events_instances.rule_instance_id AND 
		gaming_rules_instances.start_date<=dateNow
	  WHERE gaming_game_sessions.is_open=1;
		  
	  -- login sessions
	  SELECT sessions_main.session_id As session_id, sessions_main.date_open, sessions_main.status_code, sessions_main.session_type, sessions_main.extra2_id,
		gaming_rules_events.rule_event_id, gaming_events.event_id, 
        gaming_client_sessions.total_bet_real, gaming_client_sessions.total_bet_bonus, gaming_client_sessions.total_win_real, gaming_client_sessions.total_win_bonus
	  FROM sessions_main FORCE INDEX (session_type_status)
	  STRAIGHT_JOIN gaming_client_sessions ON sessions_main.session_id = gaming_client_sessions.session_id
	  STRAIGHT_JOIN gaming_rules ON gaming_rules.is_active=1 
	  STRAIGHT_JOIN gaming_event_tables ON gaming_event_tables.table_name = 'sessions_main' 
      STRAIGHT_JOIN gaming_events ON gaming_events.event_table_id = gaming_event_tables.event_table_id
      STRAIGHT_JOIN gaming_rules_events ON gaming_rules_events.rule_id=gaming_rules.rule_id AND gaming_rules_events.event_id=gaming_events.event_id
	  STRAIGHT_JOIN gaming_events_instances FORCE INDEX (player_rule_event) ON 
		(gaming_events_instances.client_stat_id=extra2_id AND 
         gaming_events_instances.rule_event_id=gaming_rules_events.rule_event_id AND gaming_events_instances.is_current=1 AND
         gaming_events_instances.is_achieved=0 AND gaming_events_instances.has_failed=0)
	  STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_instances.rule_instance_id=gaming_events_instances.rule_instance_id AND
		gaming_rules_instances.start_date<=dateNow
	  WHERE sessions_main.session_type=2 AND sessions_main.status_code=1;
  
	  SET sessionsReturned=1;
  ELSE
	  SET sessionsReturned=0;
  END IF;

  -- bets and wins   
  SELECT gaming_event_tables.event_table_id, gaming_game_plays.game_play_id, gaming_game_plays.game_round_id, gaming_payment_transaction_type.name AS transaction_type, 
	gaming_game_plays.amount_total, gaming_game_plays.amount_total_base, gaming_game_plays.amount_real, 
    gaming_game_plays.amount_bonus, gaming_game_plays.amount_bonus_win_locked, gaming_game_plays.timestamp, gaming_game_plays.game_id, 
    gaming_game_plays.client_stat_id, gaming_game_plays.game_session_id, gaming_game_plays.round_transaction_no, 
    gaming_rules_events.rule_event_id, gaming_events.event_id, gaming_game_categories_games.game_category_id, gaming_game_plays.session_id, gaming_game_plays.license_type_id
  FROM gaming_event_tables
  STRAIGHT_JOIN gaming_event_rows FORCE INDEX (event_table_rule_engine_state) ON 
	gaming_event_tables.table_name = 'gaming_game_plays' AND 
	(gaming_event_rows.event_table_id = gaming_event_tables.event_table_id AND gaming_event_rows.rule_engine_state=2) 
  STRAIGHT_JOIN gaming_rules ON gaming_rules.is_active=1
  STRAIGHT_JOIN gaming_rules_events ON gaming_rules.rule_id = gaming_rules_events.rule_id
  STRAIGHT_JOIN gaming_events ON gaming_rules_events.event_id=gaming_events.event_id AND gaming_events.event_table_id=gaming_event_tables.event_table_id
  STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.game_play_id=gaming_event_rows.elem_id
  STRAIGHT_JOIN gaming_events_instances FORCE INDEX (player_rule_event) ON 
	(gaming_events_instances.client_stat_id=gaming_game_plays.client_stat_id AND 
	 gaming_rules_events.rule_event_id=gaming_events_instances.rule_event_id AND gaming_events_instances.is_current=1 AND 
     gaming_events_instances.is_achieved=0 AND gaming_events_instances.has_failed=0)
  STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_instances.rule_instance_id=gaming_events_instances.rule_instance_id 
	AND gaming_rules_instances.start_date<=dateNow
  STRAIGHT_JOIN gaming_game_categories_games ON gaming_game_categories_games.game_id=gaming_game_plays.game_id
  STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.payment_transaction_type_id=gaming_game_plays.payment_transaction_type_id;
  
  -- deposits and withdrawals
  SELECT gaming_balance_history.balance_history_id, gaming_balance_history.client_stat_id,  amount AS Amount,
	gaming_payment_transaction_type.name AS TransactionTypeName, gaming_payment_method.name AS PaymentMethodName, timestamp, gaming_payment_method.display_name AS PaymentMethod,gaming_rules_events.rule_event_id,gaming_events.event_id, session_id, gaming_payment_method.payment_method_id
  FROM gaming_event_tables
  STRAIGHT_JOIN gaming_event_rows FORCE INDEX (event_table_rule_engine_state) ON 
	gaming_event_tables.table_name = 'gaming_balance_history' AND 
	(gaming_event_rows.event_table_id = gaming_event_tables.event_table_id AND gaming_event_rows.rule_engine_state=2) 
  STRAIGHT_JOIN gaming_rules ON gaming_rules.is_active=1
  STRAIGHT_JOIN gaming_rules_events ON gaming_rules.rule_id = gaming_rules_events.rule_id
  STRAIGHT_JOIN gaming_events ON gaming_rules_events.event_id=gaming_events.event_id AND gaming_events.event_table_id = gaming_event_tables.event_table_id 
  STRAIGHT_JOIN gaming_balance_history ON gaming_balance_history.balance_history_id=gaming_event_rows.elem_id
  STRAIGHT_JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.payment_transaction_status_id = gaming_balance_history.payment_transaction_status_id             
  STRAIGHT_JOIN gaming_balance_history_error_codes AS error_codes ON gaming_balance_history.balance_history_error_code_id=error_codes.balance_history_error_code_id 
  STRAIGHT_JOIN gaming_currency ON gaming_currency.currency_id=gaming_balance_history.currency_id
  STRAIGHT_JOIN gaming_events_instances FORCE INDEX (player_rule_event) ON 
	(gaming_events_instances.client_stat_id = gaming_balance_history.client_stat_id AND 
	 gaming_rules_events.rule_event_id=gaming_events_instances.rule_event_id AND gaming_events_instances.is_current=1 AND
	 gaming_events_instances.is_achieved=0 AND gaming_events_instances.has_failed=0)
  STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_instances.rule_instance_id=gaming_events_instances.rule_instance_id 
	AND gaming_rules_instances.start_date<=dateNow
  STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.payment_transaction_type_id = gaming_balance_history.payment_transaction_type_id
  LEFT JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id
  LEFT JOIN gaming_payment_method AS sub_payment_method ON sub_payment_method.payment_method_id = gaming_balance_history.sub_payment_method_id
  LEFT JOIN gaming_payment_gateways ON gaming_balance_history.payment_gateway_id=gaming_payment_gateways.payment_gateway_id;
  
  -- Registered Players
  SELECT gaming_client_stats.client_stat_id, gaming_clients.is_active, gaming_rules_events.rule_event_id, gaming_events.event_id, gaming_clients.referral_client_id, gaming_clients.sign_up_date
  FROM gaming_event_tables
  STRAIGHT_JOIN gaming_event_rows FORCE INDEX (event_table_rule_engine_state) ON 
	gaming_event_tables.table_name = 'gaming_clients' AND 
	(gaming_event_rows.event_table_id = gaming_event_tables.event_table_id AND gaming_event_rows.rule_engine_state=2) 
  STRAIGHT_JOIN gaming_clients ON gaming_clients.client_id=gaming_event_rows.elem_id
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active=1
  STRAIGHT_JOIN gaming_rules ON gaming_rules.is_active=1
  STRAIGHT_JOIN gaming_rules_events ON gaming_rules.rule_id = gaming_rules_events.rule_id AND gaming_rules_events.is_finished=0
  STRAIGHT_JOIN gaming_events ON gaming_rules_events.event_id=gaming_events.event_id AND gaming_events.event_table_id = gaming_event_tables.event_table_id;
  
  -- Experience Points  
  SELECT gaming_client_stats.client_stat_id,amount_given,license_type_id,time_stamp,gaming_rules_events.rule_event_id,gaming_events.event_id
  FROM gaming_event_tables 
  STRAIGHT_JOIN gaming_event_rows FORCE INDEX (event_table_rule_engine_state) ON 
	gaming_event_tables.table_name = 'gaming_clients_experience_points_transactions' AND 
	(gaming_event_rows.event_table_id = gaming_event_tables.event_table_id AND gaming_event_rows.rule_engine_state=2) 
  STRAIGHT_JOIN gaming_clients_experience_points_transactions ON gaming_clients_experience_points_transactions.experience_points_transaction_id=gaming_event_rows.elem_id
  STRAIGHT_JOIN gaming_rules ON gaming_rules.is_active=1
  STRAIGHT_JOIN gaming_rules_events ON gaming_rules.rule_id = gaming_rules_events.rule_id
  STRAIGHT_JOIN gaming_events ON gaming_rules_events.event_id=gaming_events.event_id AND gaming_events.event_table_id=gaming_event_tables.event_table_id
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_id = gaming_clients_experience_points_transactions.client_id
  STRAIGHT_JOIN gaming_events_instances FORCE INDEX (player_rule_event) ON 
	(gaming_events_instances.client_stat_id = gaming_client_stats.client_stat_id AND 
	 gaming_rules_events.rule_event_id= gaming_events_instances.rule_event_id AND gaming_events_instances.is_current=1 AND
     gaming_events_instances.is_achieved=0 AND gaming_events_instances.has_failed=0)
  STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_instances.rule_instance_id=gaming_events_instances.rule_instance_id AND
	gaming_rules_instances.start_date<=dateNow;
  
  -- Event Instance Status
  SELECT gaming_events_instances.is_current, gaming_events_instances.client_stat_id, gaming_events_instances.attr_value, gaming_events_instances.rule_event_id, gaming_rules_instances.rule_instance_id, gaming_client_stats.currency_id, UpdatedFields.end_date 
  FROM gaming_events_instances FORCE INDEX (current_events)
  STRAIGHT_JOIN gaming_rules_instances FORCE INDEX (PRIMARY) ON 
	gaming_events_instances.rule_instance_id = gaming_rules_instances.rule_instance_id AND gaming_rules_instances.is_current=1 AND
    gaming_rules_instances.start_date<=dateNow
  STRAIGHT_JOIN gaming_rules_events ON gaming_rules_events.rule_event_id = gaming_events_instances.rule_event_id AND gaming_rules_events.is_finished=0
  STRAIGHT_JOIN gaming_rules ON gaming_rules_instances.rule_id=gaming_rules.rule_id
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_events_instances.client_stat_id
  STRAIGHT_JOIN (
      SELECT gaming_game_plays.client_stat_id, gaming_rules_events.rule_event_id, gaming_rules_instances.end_date
      FROM gaming_event_tables 
      STRAIGHT_JOIN gaming_event_rows FORCE INDEX (event_table_rule_engine_state) ON 
		gaming_event_tables.table_name = 'gaming_game_plays' AND
		(gaming_event_rows.event_table_id = gaming_event_tables.event_table_id AND gaming_event_rows.rule_engine_state=2)
	  STRAIGHT_JOIN gaming_rules ON gaming_rules.is_active=1
	  STRAIGHT_JOIN gaming_rules_events ON gaming_rules_events.rule_id=gaming_rules.rule_id 
      STRAIGHT_JOIN gaming_events ON gaming_rules_events.event_id=gaming_events.event_id AND gaming_events.event_table_id = gaming_event_tables.event_table_id 
      STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.game_play_id=gaming_event_rows.elem_id
      STRAIGHT_JOIN gaming_rules_instances FORCE INDEX (client_stat_rule) ON 
		gaming_rules_instances.client_stat_id = gaming_game_plays.client_stat_id AND gaming_rules_instances.rule_id=gaming_rules.rule_id AND gaming_rules_instances.is_current=1
      GROUP BY gaming_game_plays.client_stat_id, gaming_rules_events.rule_event_id
    UNION ALL
      SELECT gaming_balance_history.client_stat_id,gaming_rules_events.rule_event_id,gaming_rules_instances.end_date
      FROM gaming_event_tables 
      STRAIGHT_JOIN gaming_event_rows FORCE INDEX (event_table_rule_engine_state) ON 
		gaming_event_tables.table_name = 'gaming_balance_history' AND
		(gaming_event_rows.event_table_id = gaming_event_tables.event_table_id AND gaming_event_rows.rule_engine_state=2)
	  STRAIGHT_JOIN gaming_rules ON gaming_rules.is_active=1
      STRAIGHT_JOIN gaming_rules_events ON gaming_rules_events.rule_id=gaming_rules.rule_id 
      STRAIGHT_JOIN gaming_events ON gaming_rules_events.event_id=gaming_events.event_id AND gaming_events.event_table_id = gaming_event_tables.event_table_id 
      STRAIGHT_JOIN gaming_balance_history ON gaming_balance_history.balance_history_id = gaming_event_rows.elem_id
      STRAIGHT_JOIN gaming_rules_instances FORCE INDEX (client_stat_rule) ON 
		gaming_rules.rule_id = gaming_rules_instances.rule_id AND gaming_rules_instances.client_stat_id = gaming_balance_history.client_stat_id AND gaming_rules_instances.is_current=1
	  GROUP BY gaming_balance_history.client_stat_id, gaming_rules_events.rule_event_id
    UNION ALL
      SELECT gaming_game_sessions.client_stat_id, gaming_rules_events.rule_event_id, gaming_rules_instances.end_date
      FROM gaming_game_sessions FORCE INDEX (is_open)
      STRAIGHT_JOIN gaming_client_stats ON gaming_game_sessions.client_stat_id=gaming_client_stats.client_stat_id
      STRAIGHT_JOIN gaming_rules ON gaming_rules.is_active=1
      STRAIGHT_JOIN gaming_rules_events ON gaming_rules.rule_id = gaming_rules_events.rule_id
      STRAIGHT_JOIN gaming_events ON gaming_rules_events.event_id=gaming_events.event_id
      STRAIGHT_JOIN gaming_event_tables ON gaming_event_tables.table_name = 'gaming_game_sessions' AND gaming_events.event_table_id = gaming_event_tables.event_table_id
      STRAIGHT_JOIN gaming_rules_instances FORCE INDEX (client_stat_rule) ON 
		gaming_rules.rule_id = gaming_rules_instances.rule_id AND gaming_rules_instances.client_stat_id = gaming_game_sessions.client_stat_id AND gaming_rules_instances.is_current=1
      WHERE gaming_game_sessions.is_open=1
      GROUP BY gaming_game_sessions.client_stat_id, gaming_rules_events.rule_event_id
    UNION ALL
      SELECT sessions_main.extra2_id, gaming_rules_events.rule_event_id, gaming_rules_instances.end_date
      FROM sessions_main FORCE INDEX (session_type_status)
      STRAIGHT_JOIN gaming_client_sessions ON sessions_main.session_id = gaming_client_sessions.session_id
      STRAIGHT_JOIN gaming_rules ON gaming_rules.is_active=1
      STRAIGHT_JOIN gaming_rules_events ON gaming_rules.rule_id = gaming_rules_events.rule_id
      STRAIGHT_JOIN gaming_events ON gaming_rules_events.event_id=gaming_events.event_id
      STRAIGHT_JOIN gaming_event_tables ON gaming_event_tables.table_name = 'sessions_main' AND gaming_events.event_table_id = gaming_event_tables.event_table_id
      STRAIGHT_JOIN gaming_rules_instances FORCE INDEX (client_stat_rule) ON 
		gaming_rules.rule_id = gaming_rules_instances.rule_id AND gaming_rules_instances.client_stat_id = sessions_main.extra2_id AND gaming_rules_instances.is_current=1
      WHERE sessions_main.session_type=2 AND sessions_main.status_code=1 
      GROUP BY sessions_main.extra2_id, gaming_rules_events.rule_event_id
    UNION ALL
      SELECT gaming_client_stats.client_stat_id, gaming_rules_events.rule_event_id, gaming_rules_instances.end_date
      FROM gaming_event_tables 
      STRAIGHT_JOIN gaming_event_rows FORCE INDEX (event_table_rule_engine_state) ON 
		gaming_event_tables.table_name = 'gaming_clients_experience_points_transactions' AND
		(gaming_event_rows.event_table_id = gaming_event_tables.event_table_id AND gaming_event_rows.rule_engine_state=2)
	  STRAIGHT_JOIN gaming_rules ON gaming_rules.is_active=1
      STRAIGHT_JOIN gaming_rules_events ON gaming_rules_events.rule_id=gaming_rules.rule_id 
      STRAIGHT_JOIN gaming_events ON gaming_rules_events.event_id=gaming_events.event_id AND gaming_events.event_table_id = gaming_event_tables.event_table_id 
      STRAIGHT_JOIN gaming_clients_experience_points_transactions ON gaming_clients_experience_points_transactions.experience_points_transaction_id=gaming_event_rows.elem_id
      STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_id = gaming_clients_experience_points_transactions.client_id
      STRAIGHT_JOIN gaming_rules_instances FORCE INDEX (client_stat_rule) ON 
		gaming_rules.rule_id = gaming_rules_instances.rule_id AND gaming_rules_instances.client_stat_id = gaming_client_stats.client_stat_id AND gaming_rules_instances.is_current=1
      GROUP BY gaming_client_stats.client_stat_id, gaming_rules_events.rule_event_id
  ) As UpdatedFields ON gaming_events_instances.client_stat_id = UpdatedFields.client_stat_id AND gaming_events_instances.rule_event_id = UpdatedFields.rule_event_id 
  WHERE (gaming_events_instances.is_current=1 AND gaming_events_instances.is_achieved=0 AND gaming_events_instances.has_failed=0)
  GROUP BY gaming_events_instances.client_stat_id, gaming_events_instances.rule_event_id; 

  /*
  	UPDATE gaming_event_rows FORCE INDEX (PRIMARY)
	JOIN
	(
	  SELECT event_table_id, elem_id FROM gaming_event_rows WHERE rule_engine_state=2
	) AS XX ON gaming_event_rows.event_table_id=XX.event_table_id AND gaming_event_rows.elem_id=XX.elem_id
	SET rule_engine_state=9;
  */
  
  UPDATE gaming_event_rows FORCE INDEX (rule_engine_state) SET rule_engine_state=9 WHERE rule_engine_state=2 LIMIT 10000;
  
  SELECT NOW() as nowTimeStamp;
  
  SELECT gaming_query_date_interval_types.name, rule_event_id 
  FROM gaming_query_date_interval_types
  JOIN gaming_rules ON query_date_interval_type_id=query_interval_type_id
  JOIN gaming_rules_events ON gaming_rules.rule_id = gaming_rules_events.rule_id;
  
  SELECT rule_event_id, count_achieved 
  FROM gaming_rules_events
  JOIN gaming_rules ON gaming_rules.rule_id = gaming_rules_events.rule_id
  WHERE is_active=1 AND is_finished=0;
  
  SELECT rule_id, rule_query FROM gaming_rules WHERE is_active = 1;
  
  IF (sessionsReturned=1) THEN
    UPDATE gaming_settings SET value_date=NOW() WHERE `name`='RULE_ENGINE_LAST_RUN_DATE';
  END IF;
END root$$

DELIMITER ;

