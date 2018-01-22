DROP procedure IF EXISTS `TableCompressAllDatabases`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TableCompressAllDatabases`(dbWildCard VARCHAR(80))
BEGIN

    -- Keep only in DBV 

	DECLARE dbName VARCHAR(128);
	DECLARE noMoreRecords TINYINT(1) DEFAULT 0;
	
	DECLARE dbCursor CURSOR FOR 
		SELECT SCHEMA_NAME AS `database` FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME LIKE dbWildCard;
	  DECLARE CONTINUE HANDLER FOR NOT FOUND
		SET noMoreRecords = 1;
    
	OPEN dbCursor;
	dbLabel: LOOP 
    
		SET noMoreRecords=0;
		FETCH dbCursor INTO dbName;
		IF (noMoreRecords) THEN
		  LEAVE dbLabel;
		END IF;
	  
		-- Change Database Context
        -- !!!! Not Supported Yet By MySQL
        SET @alterStatement=CONCAT('USE `', dbName, '`;');			
		PREPARE stmt1 FROM @alterStatement;
		EXECUTE stmt1;
		DEALLOCATE PREPARE stmt1;

		-- Create Table
		DROP TABLE IF EXISTS `gaming_table_for_compression`;
		CREATE TABLE `gaming_table_for_compression` (
		  `table_name` VARCHAR(128) NOT NULL,
		  `block_size` INT NOT NULL DEFAULT 4,
		  `is_compressed` TINYINT(1) NOT NULL DEFAULT 0,
		  PRIMARY KEY (`table_name`));
		  
		-- Insert table to compress
        INSERT INTO gaming_table_for_compression (`table_name`) VALUES
		('gaming_game_plays_bonus_instances'),
		('gaming_game_plays_bonus_instances_wins'),
		('gaming_game_rounds'),
		('gaming_game_rounds_lottery'),
		('gaming_game_plays'),
		('gaming_game_play_ring_fenced'),
		('gaming_game_plays_lottery_entries'),
		('gaming_transactions'),
		('gaming_balance_history'),
		('gaming_cw_transactions'),
		('gaming_game_plays_process_counter'),
		('gaming_game_plays_win_counter'),
		('gaming_game_plays_win_counter_bets'),
		('gaming_game_sessions'),
		('sessions_main'),
		('gaming_client_daily_balances'),
		('gaming_client_payment_info'),
		('history_gaming_clients'),
		('history_clients_locations'),
		('gaming_sb_bets'),
		('gaming_sb_bet_wins'),
		('gaming_sb_bet_singles'),
		('gaming_sb_bet_multiples'),
		('gaming_sb_bet_multiples_singles'),
		('gaming_sb_bets_bonuses'),
		('gaming_sb_bets_bonus_rules'),
		('gaming_sb_bet_history'),
		('gaming_lottery_coupons'),
		('gaming_lottery_coupon_games'),
		('gaming_lottery_dbg_tickets'),
		('gaming_lottery_dbg_ticket_entries'),
		('gaming_lottery_dbg_ticket_entry_boards'),
		('gaming_lottery_dbg_ticket_entry_board_numbers'),
		('gaming_lottery_participations'),
		('gaming_lottery_participation_prizes'),
		('gaming_log_service_calls'),
		('gaming_log_simples'),
		('gaming_log_external_calls'),
		('gaming_log_payment_calls'),
		('gaming_job_runs'),
		('gaming_cw_requests'),
		('gaming_cw_request_transactions'),
		('gaming_cw_tokens'),
		('gaming_affiliate_client_activity_transfers'),
		('gaming_affiliate_client_activity_transfers_sent'),
		('gaming_affiliate_client_transfers'),
		('gaming_affiliate_client_transfers_sent'),
		('gaming_player_selections_player_cache'),
		('gaming_player_selections_player_cache_history'),
		('gaming_player_selections_player_extension_history'),
		('gaming_player_selections_dynamic_filter_players'),
		('gaming_client_segments_players'),
		('gaming_recommendations_result_cache_player')
		ON DUPLICATE KEY UPDATE is_compressed=is_compressed;
  
		-- Compress Tables
		CALL TableCompressTables(dbName);

	END LOOP dbLabel;
	CLOSE dbCursor;

END$$

DELIMITER ;

