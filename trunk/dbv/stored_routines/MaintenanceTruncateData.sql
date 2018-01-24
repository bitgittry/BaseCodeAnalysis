DROP procedure IF EXISTS `MaintenanceTruncateData`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `MaintenanceTruncateData`()
BEGIN

  -- Optimized
  -- Need to opitimize pool betting 
  
  COMMIT;
  SET @logsKeepFromDate=DATE_SUB(NOW(), INTERVAL 30 DAY);
  SET @countersKeepFromDate=DATE_SUB(NOW(), INTERVAL 5 DAY);
  SET @affiliateTransferFromDate=DATE_SUB(NOW(), INTERVAL 60 DAY);
  SET @sleepSeconds=0.001;

  REPEAT SET @rowCount=0; DELETE FROM gaming_log_service_calls WHERE time_end<@logsKeepFromDate LIMIT 10000; SET @rowCount=ROW_COUNT(); SELECT SLEEP(@sleepSeconds) INTO @sreturn; UNTIL @rowCount<10000 END REPEAT;
  REPEAT SET @rowCount=0; DELETE FROM gaming_log_simples WHERE date_added<@logsKeepFromDate LIMIT 10000; SET @rowCount=ROW_COUNT(); SELECT SLEEP(@sleepSeconds) INTO @sreturn; UNTIL @rowCount<10000 END REPEAT;
  REPEAT SET @rowCount=0; DELETE FROM gaming_log_external_calls WHERE time_end<@logsKeepFromDate LIMIT 10000; SET @rowCount=ROW_COUNT(); SELECT SLEEP(@sleepSeconds) INTO @sreturn; UNTIL @rowCount<10000 END REPEAT;
  REPEAT SET @rowCount=0; DELETE FROM gaming_log_payment_calls WHERE time_end<@logsKeepFromDate LIMIT 10000; SET @rowCount=ROW_COUNT(); SELECT SLEEP(@sleepSeconds) INTO @sreturn; UNTIL @rowCount<10000 END REPEAT;
  REPEAT SET @rowCount=0; DELETE FROM gaming_job_runs WHERE end_date<@logsKeepFromDate LIMIT 10000; SET @rowCount=ROW_COUNT(); SELECT SLEEP(@sleepSeconds) INTO @sreturn; UNTIL @rowCount<10000 END REPEAT;
  REPEAT SET @rowCount=0; DELETE FROM gaming_cw_requests WHERE timestamp<@logsKeepFromDate LIMIT 10000; SET @rowCount=ROW_COUNT(); SELECT SLEEP(@sleepSeconds) INTO @sreturn; UNTIL @rowCount<10000 END REPEAT;
  SET @cwRequestID=0; SELECT cw_request_id INTO @cwRequestID FROM gaming_cw_requests ORDER BY cw_request_id ASC LIMIT 1;	
  REPEAT SET @rowCount=0; DELETE FROM gaming_cw_request_transactions WHERE cw_request_id<@cwRequestID LIMIT 10000; SET @rowCount=ROW_COUNT(); SELECT SLEEP(@sleepSeconds) INTO @sreturn; UNTIL @rowCount<10000 END REPEAT;
  REPEAT SET @rowCount=0; DELETE FROM gaming_cw_tokens WHERE created_date<@logsKeepFromDate LIMIT 20000; SET @rowCount=ROW_COUNT(); SELECT SLEEP(@sleepSeconds) INTO @sreturn; UNTIL @rowCount<20000 END REPEAT;

  REPEAT
	  SET @rowCount=0;
	  DELETE FROM gaming_array_counter LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT();  
	  DELETE FROM gaming_balance_deposit_process_counter LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT(); 
	  DELETE FROM gaming_balance_deposit_process_counter_deposits LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT(); 
	  DELETE FROM gaming_balance_withdrawal_process_counter LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT();  
	  DELETE FROM gaming_balance_withdrawal_process_counter_withdrawals LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT(); 
  UNTIL @rowCount<10000 END REPEAT;
  
  SET @counterID = 0; SET @counterID = (SELECT MAX(bonus_lost_counter_id) FROM gaming_bonus_lost_counter);
  DELETE FROM gaming_bonus_lost_counter WHERE num_bonuses=0 AND bonus_lost_counter_id<@counterID; 
  
  REPEAT
	  SET @rowCount=0;
	  DELETE FROM gaming_bonus_rule_get_counter LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT(); 
	  DELETE FROM gaming_client_stats_favourite_games_counter LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT();
	  DELETE FROM gaming_game_plays_process_counter LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT();
	  DELETE FROM gaming_game_plays_process_counter_bets LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT();
	  DELETE FROM gaming_game_plays_process_counter_rounds LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT();
  UNTIL @rowCount<10000 END REPEAT;
  
  SET @counterID = 0; SET @counterID = (SELECT MAX(game_play_win_counter_id) FROM gaming_game_plays_win_counter);
  REPEAT SET @rowCount=0; DELETE FROM gaming_game_plays_win_counter WHERE game_play_win_counter_id < @counterID LIMIT 20000; SET @rowCount=ROW_COUNT(); SELECT SLEEP(@sleepSeconds) INTO @sreturn; UNTIL @rowCount<20000 END REPEAT;

  SET @counterID = 0; SET @counterID = (SELECT MAX(game_play_bet_counter_id) FROM gaming_game_plays_bet_counter);
  REPEAT SET @rowCount=0; DELETE FROM gaming_game_plays_bet_counter WHERE game_play_bet_counter_id < @counterID LIMIT 20000; SET @rowCount=ROW_COUNT(); SELECT SLEEP(@sleepSeconds) INTO @sreturn; UNTIL @rowCount<20000 END REPEAT;
  
  REPEAT
	  SET @rowCount=0;
	  DELETE FROM gaming_lock_client_counter LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT();   
	  DELETE FROM gaming_player_selection_counter LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT();
	  DELETE FROM gaming_player_selection_counter_players LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT();
	  DELETE FROM gaming_promotion_get_counter LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT(); 
	  DELETE FROM gaming_promotion_get_counter_promotions LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT();
	  DELETE FROM sessions_close_counters LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT();
	  DELETE FROM sessions_close_counters_sessions LIMIT 5000; SET @rowCount=@rowCount+ROW_COUNT();
  UNTIL @rowCount<10000 END REPEAT;
  
  DELETE gaming_pb_fixture_rem_unit_history
  FROM gaming_pb_fixture_rem_unit_history  
  JOIN gaming_pb_fixture_pool_history_type fpht ON gaming_pb_fixture_rem_unit_history.pb_fixture_pool_history_type_id = fpht.pb_fixture_pool_history_type_id
  JOIN gaming_pb_pools ON fpht.pb_pool_id = gaming_pb_pools.pb_pool_id
  JOIN gaming_pb_pool_statuses ON gaming_pb_pool_statuses.pb_status_id = gaming_pb_pools.pb_status_id
  WHERE gaming_pb_pool_statuses.name = 'OFFICIAL' AND rem_units_updated_timestamp < DATE_SUB(NOW(), INTERVAL 1460 HOUR) 
  AND gaming_pb_fixture_rem_unit_history.pb_fixture_pool_history_type_id > 0 AND gaming_pb_fixture_rem_unit_history.pb_outcome_id > 0; 

  DELETE gaming_pb_fixture_history
  FROM gaming_pb_fixture_history  
  JOIN gaming_pb_pools ON gaming_pb_fixture_history.pb_pool_id = gaming_pb_pools.pb_pool_id
  JOIN gaming_pb_pool_statuses ON gaming_pb_pool_statuses.pb_status_id = gaming_pb_pools.pb_status_id
  WHERE gaming_pb_pool_statuses.name = 'OFFICIAL' AND rem_units_updated_timestamp < DATE_SUB(NOW(), INTERVAL 1460 HOUR); 	

END$$

DELIMITER ;

