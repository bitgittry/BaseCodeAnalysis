-- -------------------------------------
-- LotteryGetCouponByID.sql
-- -------------------------------------

DROP procedure IF EXISTS `LotteryGetCouponByID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LotteryGetCouponByID`(lotteryCouponID BIGINT)
BEGIN
	-- Syndicates and Combos  
    
    DECLARE isBankerFalse, cashOutNotEnabled TINYINT(1) DEFAULT 0;
    DECLARE VerticalVersion INT(11) DEFAULT 0;
    
  SELECT IFNULL(vertical_version,0) INTO VerticalVersion FROM gaming_lottery_coupons WHERE lottery_coupon_id=lotteryCouponID; 
	-- coupon (0) 
	SELECT coupon.lottery_coupon_id, @license_type_id:=coupon.license_type_id AS license_type_id, gaming_license_type.`name` AS license_type, coupon.lottery_coupon_idf, coupon.game_manufacturer_id, coupon.client_stat_id, coupon.discount, coupon.promotions, coupon.coupon_date,
	  coupon.coupon_cost, coupon.cancel_date, coupon_status.status_code AS lottery_coupon_status_code, coupon_status.description AS lottery_coupon_status_description, coupon_type.coupon_type_code AS lottery_coupon_type_code, coupon_type.description AS lottery_coupon_type_description, 
	  wager_status.name AS lottery_wager_status_name, wager_status.description AS lottery_wager_status_description, coupon.error_code,
	  retailer.lottery_retailer_id, retailer.retailer_idf AS lottery_retailer_idf, terminal.lottery_retailer_terminal_id, terminal.terminal_idf AS lottery_retailer_terminal_idf, employee.lottery_retailer_employee_id, employee.employee_idf AS lottery_retailer_employee_idf,
	  coupon.num_games, coupon.num_tickets, coupon.num_ticket_entries, coupon.num_participations, coupon.display_name, 
	  coupon.is_active, coupon.win_gross_amount, coupon.win_net_amount, coupon.win_tax_amount, coupon.win_amount, 
	  coupon.client_loyalty_card_number_id, loyalty_card.card_number AS loyalty_card_number, games.manufacturer_game_idf AS primary_game_ref,
	  coupon.lottery_subscription_id, cancel_reason,
	  gcflc.favourite_description,
	  syndicates.syndicate_idf, syndicates.name AS syndicate_name, syndicates.total_no_of_shares AS syndicate_total_no_of_shares, combos.combo_idf, combos.name AS combo_name, coupon.last_played AS favourite_last_played_on, coupon.paid_with, 
				coupon.channel_type_id, gaming_channel_types.channel_type, coupon.platform_type_id, gaming_platform_types.platform_type, gcflc.lottery_coupon_id as favourite_coupon_id, coupon.win_notification,
        coupon.loss_notification, VerticalVersion as vertical_version
        
	FROM gaming_lottery_coupons AS coupon FORCE INDEX (PRIMARY)
	STRAIGHT_JOIN gaming_license_type ON gaming_license_type.license_type_id = coupon.license_type_id
	STRAIGHT_JOIN gaming_lottery_coupon_statuses AS coupon_status ON coupon.lottery_coupon_status_id=coupon_status.lottery_coupon_status_id
	STRAIGHT_JOIN gaming_lottery_coupon_types AS coupon_type ON coupon.lottery_coupon_type_id=coupon_type.lottery_coupon_type_id 
	STRAIGHT_JOIN gaming_lottery_wager_statuses AS wager_status ON coupon.lottery_wager_status_id=wager_status.lottery_wager_status_id 
	STRAIGHT_JOIN gaming_lottery_dbg_tickets AS primary_game ON coupon.lottery_coupon_id = primary_game.lottery_coupon_id AND primary_game.is_primary_game=1
	STRAIGHT_JOIN gaming_games AS games ON primary_game.game_id = games.game_id
	LEFT JOIN gaming_lottery_retailers AS retailer ON coupon.lottery_retailer_id=retailer.lottery_retailer_id
	LEFT JOIN gaming_lottery_retailer_terminals AS terminal ON coupon.lottery_retailer_terminal_id=terminal.lottery_retailer_terminal_id
	LEFT JOIN gaming_lottery_retailer_employees AS employee ON coupon.lottery_retailer_employee_id=employee.lottery_retailer_employee_id
	LEFT JOIN gaming_client_loyalty_cards AS loyalty_card ON coupon.client_loyalty_card_number_id=loyalty_card.client_loyalty_card_number_id
	LEFT JOIN gaming_lottery_syndicates AS syndicates ON coupon.lottery_syndicate_id = syndicates.lottery_syndicate_id
	LEFT JOIN gaming_lottery_combos AS combos ON coupon.lottery_combo_id = combos.lottery_combo_id
	LEFT JOIN gaming_platform_types ON coupon.platform_type_id = gaming_platform_types.platform_type_id
	LEFT JOIN gaming_channel_types ON coupon.channel_type_id = gaming_channel_types.channel_type_id
	LEFT JOIN gaming_client_favourite_lottery_coupons as gcflc ON coupon.favourite_coupon_id = gcflc.favourite_coupon_id
	WHERE coupon.lottery_coupon_id=lotteryCouponID; 

	-- transaction (1)
	SELECT transaction.lottery_transaction_id, transaction_type.type_code AS lottery_transaction_type_code, transaction_type.description AS lottery_transaction_type_description, channel.channel_code AS lottery_channel_code, channel.description AS lottery_channel_description, transaction.transaction_time, transaction.status, transaction.lottery_transaction_idf
	FROM gaming_lottery_coupons AS coupon
	STRAIGHT_JOIN gaming_lottery_transactions AS transaction ON coupon.lottery_coupon_id=transaction.lottery_coupon_id AND is_bet_transaction = 1
	LEFT JOIN gaming_lottery_transaction_types AS transaction_type ON transaction.lottery_transaction_type_id=transaction_type.lottery_transaction_type_id
	STRAIGHT_JOIN gaming_lottery_channels AS channel ON transaction.lottery_channel_id=channel.lottery_channel_id
	WHERE coupon.lottery_coupon_id=lotteryCouponID
	ORDER by lottery_transaction_id DESC
    LIMIT 1; 

	-- ticket (2)
	SELECT ticket.lottery_dbg_ticket_id, ticket.lottery_coupon_id, ticket.game_manufacturer_id, ticket.multi_draws, ticket.game_state_idf, ticket.first_draw_number, ticket.last_draw_number,
	  ticket.promo_code_idf, ticket.advance_draws, ticket.extra_flag, ticket.robot_last_draw_number_sent, ticket.robot_offset_from_interval_minutes, ticket.robot_jackpot_min_value, ticket.ticket_cost,
	  ticket.selection_source, ticket.game_type, ticket.multiplier
	FROM gaming_lottery_dbg_tickets AS ticket FORCE INDEX (lottery_coupon_id)
	WHERE ticket.lottery_coupon_id=lotteryCouponID;
	
	-- Lottery 
	IF (@license_type_id = 6) THEN
		-- ticket entries (3)
		SELECT ticket_entry.lottery_dbg_ticket_entry_id, ticket_entry.lottery_dbg_ticket_id, ticket_entry.topup, ticket_entry.quick_numbers, ticket_entry.quick_jokers, ticket_entry.group_name, ticket_entry.group_multiplier, ticket_entry.numbers, ticket_entry.jokers, ticket_entry.extra_numbers,
		ticket_entry.group_number, ticket_entry.system_selection, ticket_entry.selection_source, ticket_entry.game_type, ticket_entry.multiplier, ticket_entry.quickpick_selection
		, GROUP_CONCAT(DISTINCT gaming_lottery_dbg_ticket_entry_game_types_multipliers.game_type) AS game_types
		, GROUP_CONCAT(DISTINCT gaming_lottery_dbg_ticket_entry_game_types_multipliers.multiplier) AS multipliers
		FROM gaming_lottery_dbg_tickets AS tickets FORCE INDEX (lottery_coupon_id)
		STRAIGHT_JOIN gaming_lottery_dbg_ticket_entries AS ticket_entry ON tickets.lottery_dbg_ticket_id=ticket_entry.lottery_dbg_ticket_id
		LEFT JOIN gaming_lottery_dbg_ticket_entry_game_types_multipliers
		ON ticket_entry.lottery_dbg_ticket_entry_id = gaming_lottery_dbg_ticket_entry_game_types_multipliers.lottery_dbg_ticket_entry_id		
		WHERE tickets.lottery_coupon_id=lotteryCouponID
		group by ticket_entry.lottery_dbg_ticket_entry_id;

		-- ticket entry boards (4)
		SELECT board.lottery_dbg_ticket_entry_board_id, board.lottery_dbg_ticket_entry_id, ticket_entry.lottery_dbg_ticket_id, board.board_idf, board.numbers, board.board_type_idf, board.quickpick_selection
		FROM gaming_lottery_dbg_tickets AS tickets FORCE INDEX (lottery_coupon_id)
		STRAIGHT_JOIN gaming_lottery_dbg_ticket_entries AS ticket_entry ON tickets.lottery_dbg_ticket_id=ticket_entry.lottery_dbg_ticket_id
		STRAIGHT_JOIN gaming_lottery_dbg_ticket_entry_boards AS board ON ticket_entry.lottery_dbg_ticket_entry_id=board.lottery_dbg_ticket_entry_id
		WHERE tickets.lottery_coupon_id=lotteryCouponID;
	ELSE
		-- ticket_entries (3)
		SELECT NULL;
		-- ticket entry board (4)        
		SELECT NULL;
		
	END IF;
	
	-- SportsPool
	IF (@license_type_id = 7) THEN	
		-- ticket groups (5)	
		SELECT ticket_groups.lottery_dbg_ticket_group_id, ticket_groups.lottery_dbg_ticket_id, ticket_groups.group_number, ticket_groups.no_of_combinations
		FROM gaming_lottery_dbg_tickets AS tickets FORCE INDEX (lottery_coupon_id)
		STRAIGHT_JOIN gaming_lottery_dbg_ticket_groups AS ticket_groups ON tickets.lottery_dbg_ticket_id=ticket_groups.lottery_dbg_ticket_id
		WHERE tickets.lottery_coupon_id=lotteryCouponID;

		-- ticket events (6)
		SELECT ticket_groups.lottery_dbg_ticket_group_id, tickets.lottery_dbg_ticket_id, selections.lottery_draw_event_id, draw_events.lottery_draw_event_idf, draw_events.order_no, ticket_groups.group_number,
		GROUP_CONCAT(outcome_type_options.outcome_code ORDER BY outcome_type_options.`order` ASC) AS outcome_codes
		FROM gaming_lottery_dbg_tickets AS tickets FORCE INDEX (lottery_coupon_id)
		STRAIGHT_JOIN gaming_lottery_dbg_ticket_groups AS ticket_groups ON ticket_groups.lottery_dbg_ticket_id=tickets.lottery_dbg_ticket_id
		STRAIGHT_JOIN gaming_lottery_dbg_tickets_sportspool_selections AS selections ON selections.lottery_dbg_ticket_group_id=ticket_groups.lottery_dbg_ticket_group_id
		STRAIGHT_JOIN gaming_lottery_draw_events AS draw_events ON draw_events.lottery_draw_event_id = selections.lottery_draw_event_id
		STRAIGHT_JOIN gaming_lottery_draws AS draws ON draws.lottery_draw_id = draw_events.lottery_draw_id
		STRAIGHT_JOIN gaming_games AS games ON games.game_id = draws.game_id
		STRAIGHT_JOIN gaming_game_outcome_type_options AS outcome_type_options ON outcome_type_options.`order` = selections.game_outcome_type_option_id 
		AND outcome_type_options.game_outcome_type_id=COALESCE(draw_events.game_outcome_type_id, draws.game_outcome_type_id, games.game_outcome_type_id)
		WHERE tickets.lottery_coupon_id=lotteryCouponID
		GROUP BY draw_events.lottery_draw_event_id, selections.lottery_dbg_ticket_group_id;

	ELSE
		-- ticket_groups (5)
		SELECT NULL;
		-- ticket_events (6)
		SELECT NULL;		
	END IF;

	-- participation (7)
	SELECT participation.lottery_participation_id, participation.lottery_draw_id, participation.lottery_dbg_ticket_id, participation.game_state_idf, participation.draw_number, participation.participation_idf, participation.game_manufacturer_id,
	  participation.draw_offset, gaming_lottery_draws.draw_date, participation_status.status_code AS lottery_participation_status_code, participation_status.description AS lottery_participation_status_description, participation.participation_cost,   
	  wager_status.name AS lottery_wager_status_name, wager_status.description AS lottery_wager_status_description, participation.error_code, participation_status_for_block.status_code AS block_level, gaming_lottery_draws.visual_draw_id AS visual_draw_id
	FROM gaming_lottery_dbg_tickets AS tickets FORCE INDEX (lottery_coupon_id)
	STRAIGHT_JOIN gaming_lottery_participations AS participation ON tickets.lottery_dbg_ticket_id=participation.lottery_dbg_ticket_id
	STRAIGHT_JOIN gaming_lottery_participation_statuses AS participation_status ON participation.lottery_participation_status_id=participation_status.lottery_participation_status_id
	STRAIGHT_JOIN gaming_lottery_wager_statuses AS wager_status ON participation.lottery_wager_status_id=wager_status.lottery_wager_status_id
	STRAIGHT_JOIN gaming_lottery_draws ON participation.lottery_draw_id=gaming_lottery_draws.lottery_draw_id
	LEFT JOIN gaming_lottery_participation_statuses AS participation_status_for_block ON participation.block_level=participation_status_for_block.lottery_participation_status_id
	WHERE tickets.lottery_coupon_id=lotteryCouponID;

	-- participation_prize (8)
	SELECT participation_prize.lottery_participation_prize_id, participation_prize.lottery_participation_id, participation_prize.gross, credit_type.external_code AS credit_type_code, credit_type.description AS credit_type_description, 
	  participation_prize.refund, participation_prize.prize_status, participation_prize.gift_id, participation_prize.gift_description, participation_prize.net, approval_status.external_code AS approval_status_code, approval_status.description AS approval_status_description, participation_prize.approval_last_update,
				participation_prize.retailer_id, participation_prize.paid_with, participation_prize.channel_type_id, gaming_channel_types.channel_type, participation_prize.platform_type_id, gaming_platform_types.platform_type,
        participation_prize.bet_ref as bet_ref, participation_prize.transaction_ref as transaction_ref, IFNULL(participation_prize.cashed_out,0) as cashed_out
	FROM gaming_lottery_dbg_tickets AS tickets
	STRAIGHT_JOIN gaming_lottery_participations AS participation ON tickets.lottery_coupon_id=lotteryCouponID
	  AND tickets.lottery_dbg_ticket_id=participation.lottery_dbg_ticket_id 
	STRAIGHT_JOIN gaming_lottery_participation_prizes AS participation_prize ON participation.lottery_participation_id=participation_prize.lottery_participation_id
	STRAIGHT_JOIN gaming_lottery_participation_prize_credit_types AS credit_type ON participation_prize.credit_type_id=credit_type.credit_type_id
	STRAIGHT_JOIN gaming_lottery_participation_prize_approval_statuses AS approval_status ON participation_prize.approval_status_id=approval_status.approval_status_id
			  LEFT JOIN gaming_platform_types ON participation_prize.platform_type_id = gaming_platform_types.platform_type_id
			  LEFT JOIN gaming_channel_types ON participation_prize.channel_type_id = gaming_channel_types.channel_type_id;

	-- coupon_promotion (9)
	SELECT DATA, winning_amount, promotion_type 
	FROM gaming_lottery_coupon_promotions FORCE INDEX (lottery_coupon_id)
	WHERE lottery_coupon_id=lotteryCouponID;


	-- SportsBook
	IF (@license_type_id = 3) THEN
		-- SB Ticket (10)
    if (VerticalVersion=0) THEN
  		SELECT 0.00 as bet_amount, null as bet_ref, null as win_type, gaming_lottery_dbg_tickets.lottery_dbg_ticket_id, gaming_lottery_dbg_tickets.game_state_idf, 
  			gaming_lottery_dbg_tickets.multiplier, gaming_sb_bets.use_free_bet as use_free_bet, gaming_sb_bets.sb_bet_type_id, 
  			gaming_sb_bets.device_type, @sbBetID := gaming_sb_bets.sb_bet_id, @numMultiples := gaming_sb_bets.num_multiplies, cashOutNotEnabled as cash_out_enabled, cashOutNotEnabled as cashed_out
  		FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
  		JOIN gaming_sb_bets ON gaming_sb_bets.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
  		WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = lotteryCouponID;
		ELSE
  		SELECT gaming_sb_bet_multiples.bet_amount, gaming_sb_bet_multiples.bet_ref, gaming_sb_bet_multiples.wintype as win_type,  gaming_lottery_dbg_tickets.lottery_dbg_ticket_id, gaming_lottery_dbg_tickets.game_state_idf, 
  			gaming_lottery_dbg_tickets.multiplier, gaming_sb_bets.use_free_bet as use_free_bet, gaming_sb_bets.sb_bet_type_id, 
  			gaming_sb_bets.device_type, @sbBetID := gaming_sb_bets.sb_bet_id, @numMultiples := gaming_sb_bets.num_multiplies, cash_out_enabled as cash_out_enabled, cashed_out as cashed_out
  		FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
  		JOIN gaming_sb_bets ON gaming_sb_bets.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
      JOIN gaming_sb_bet_multiples ON gaming_sb_bet_multiples.sb_bet_id = gaming_sb_bets.sb_bet_id
  		WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = lotteryCouponID
      UNION ALL
  		SELECT gaming_sb_bet_singles.bet_amount, gaming_sb_bet_singles.bet_ref, gaming_sb_bet_singles.wintype as win_type, gaming_lottery_dbg_tickets.lottery_dbg_ticket_id, gaming_lottery_dbg_tickets.game_state_idf, 
  			gaming_lottery_dbg_tickets.multiplier, gaming_sb_bets.use_free_bet as use_free_bet, gaming_sb_bets.sb_bet_type_id, 
  			gaming_sb_bets.device_type, @sbBetID := gaming_sb_bets.sb_bet_id, @numMultiples := gaming_sb_bets.num_multiplies, cash_out_enabled as cash_out_enabled, cashed_out as cashed_out
  		FROM gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
  		JOIN gaming_sb_bets ON gaming_sb_bets.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
      JOIN gaming_sb_bet_singles ON gaming_sb_bet_singles.sb_bet_id = gaming_sb_bets.sb_bet_id
  		WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = lotteryCouponID;
      -- group by gaming_sb_bets.sb_bet_id;
    END IF;
    
    -- SB Multiple Types (11)    
    if (VerticalVersion=0) THEN
  		SELECT ext_multiple_type,multiplier, combination_size, is_system_bet, num_combinations, bet_ref
  		FROM 
  		(
  			SELECT ext_multiple_type, gaming_sb_bet_multiples.multiplier, combination_size, is_system_bet, num_combinations, gaming_sb_bet_multiples.bet_ref as bet_ref
  			FROM gaming_sb_bets 
  			JOIN gaming_sb_bet_multiples ON gaming_sb_bet_multiples.sb_bet_id = gaming_sb_bets.sb_bet_id
  			JOIN gaming_sb_multiple_types ON gaming_sb_multiple_types.sb_multiple_type_id = gaming_sb_bet_multiples.sb_multiple_type_id
  			WHERE @sbBetID = gaming_sb_bets.sb_bet_id
  		UNION 
  			SELECT 'Singles', gaming_sb_bet_singles.multiplier, 1 AS combination_size, 0 AS is_system_bet, 1 AS num_combinations, gaming_sb_bet_singles.bet_ref as bet_ref
  			FROM gaming_sb_bets 
  			JOIN gaming_sb_bet_singles ON gaming_sb_bet_singles.sb_bet_id = gaming_sb_bets.sb_bet_id
  			WHERE @sbBetID = gaming_sb_bets.sb_bet_id 
        GROUP BY gaming_sb_bets.sb_bet_id 
  		) AS multiples;
		ELSE
  		SELECT ext_multiple_type,multiplier, combination_size, is_system_bet, num_combinations, bet_ref
  		FROM 
  		(
  			SELECT ext_multiple_type, gaming_sb_bet_multiples.multiplier, combination_size, is_system_bet, num_combinations, gaming_sb_bet_multiples.bet_ref as bet_ref
  			FROM gaming_sb_bets 
  			JOIN gaming_sb_bet_multiples ON gaming_sb_bet_multiples.sb_bet_id = gaming_sb_bets.sb_bet_id
  			JOIN gaming_sb_multiple_types ON gaming_sb_multiple_types.sb_multiple_type_id = gaming_sb_bet_multiples.sb_multiple_type_id
  			WHERE @sbBetID = gaming_sb_bets.sb_bet_id
  		UNION ALL
  			SELECT 'Singles', gaming_sb_bet_singles.multiplier, 1 AS combination_size, 0 AS is_system_bet, 1 AS num_combinations, gaming_sb_bet_singles.bet_ref as bet_ref
  			FROM gaming_sb_bets 
  			JOIN gaming_sb_bet_singles ON gaming_sb_bet_singles.sb_bet_id = gaming_sb_bets.sb_bet_id
  			WHERE @sbBetID = gaming_sb_bets.sb_bet_id 
        GROUP BY gaming_sb_bets.sb_bet_id, bet_ref
  		) AS multiples;
  END IF;
    
    
    
    if (VerticalVersion=0) THEN    
  		IF (@numMultiples > 0) THEN
  			-- Events (12)
  			SELECT ext_event_id, ext_market_id, ext_selection_id, ms.odd, is_banker, m.bet_ref as bet_ref
  			FROM gaming_sb_bet_multiples AS m
  			JOIN gaming_sb_bet_multiples_singles AS ms ON ms.sb_bet_multiple_id = m.sb_bet_multiple_id
  			WHERE sb_bet_id = @sbBetID
  			GROUP BY sb_selection_id;
  		ELSE
  			-- Events (12)
  			SELECT ext_event_id, ext_market_id, ext_selection_id, odd, isBankerFalse AS is_banker, gaming_sb_bet_singles.bet_ref as bet_ref
  			FROM gaming_sb_bet_singles
  			WHERE sb_bet_id = @sbBetID;
  		END IF;
		ELSE
  			SELECT ext_event_id, ext_market_id, ext_selection_id, ms.odd, is_banker AS is_banker, m.bet_ref as bet_ref
  			FROM gaming_sb_bet_multiples AS m
  			JOIN gaming_sb_bet_multiples_singles AS ms ON ms.sb_bet_multiple_id = m.sb_bet_multiple_id
  			WHERE sb_bet_id = @sbBetID
  			GROUP BY sb_selection_id
  		UNION ALL
  			SELECT ext_event_id, ext_market_id, ext_selection_id, odd, isBankerFalse AS is_banker, gaming_sb_bet_singles.bet_ref as bet_ref
  			FROM gaming_sb_bet_singles
  			WHERE sb_bet_id = @sbBetID;    
    END IF;
    
        -- Events extra params (13)
		SELECT ext_selection_id,`name`,`value`
		FROM gaming_sb_bet_selection_extra_param
		WHERE sb_bet_id = @sbBetID
		ORDER BY ext_selection_id;



	ELSE
		-- SB Ticket (10)
		SELECT NULL;
		-- SB Multiple Types (11)
		SELECT NULL;
		-- Events (12)
		SELECT NULL;
		-- Events extra params (13)
		SELECT NULL;
		-- (14)
		SELECT NULL;	
	END IF;
END$$

DELIMITER ;

