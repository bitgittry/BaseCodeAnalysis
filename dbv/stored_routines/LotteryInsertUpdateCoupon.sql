DROP procedure IF EXISTS `LotteryInsertUpdateCoupon`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LotteryInsertUpdateCoupon`(
  couponIDF VARCHAR(40), couponStatusCode VARCHAR(40), coupontypeCode VARCHAR(40), wagerStatus VARCHAR(40), loyaltyCardNumber VARCHAR(40), retailerIDF VARCHAR(40), terminalIDF VARCHAR(40), employeeIDF  VARCHAR(40),
  tranIDF VARCHAR(40),tranTypeCode VARCHAR(40), tranChannelCode VARCHAR(40),
  discount DECIMAL(18,5), couponCost DECIMAL(18,5), winGross DECIMAL(18,5), winNet DECIMAL(18,5), winTax DECIMAL(18,5), winAmount DECIMAL(18,5),
  promotions VARCHAR(80),
  couponDate DATETIME, cancelDate DATETIME, tranTime DATETIME,
  numGames INT(11), numTickets INT(11), numTicketEntries INT(11), numParticipations INT(11), tranStatus INT(11),
  displayName VARCHAR(255),
  lotterySubscriptionId BIGINT(20), clientStatId BIGINT(20), gameManufacturerId BIGINT(20),
  clientID BIGINT,
  OUT couponID BIGINT)
BEGIN
   -- Merge to INPH 
   -- Removed Participations instead calling LotteryCreateParticipations

	-- START General Parameters
	DECLARE lotteryTranID BIGINT(20);
	-- END General Parameters

	INSERT INTO gaming_lottery_transactions (lottery_transaction_type_id, lottery_channel_id, transaction_time, status, lottery_transaction_idf, game_manufacturer_id)
	SELECT gltt.lottery_transaction_type_id, glc.lottery_channel_id, tranTime, tranStatus, tranIDF, gameManufacturerId
	FROM gaming_lottery_transaction_types gltt
	JOIN gaming_lottery_channels glc ON 
		(gltt.type_code=tranTypeCode AND gltt.game_manufacturer_id=gameManufacturerId)
		AND (glc.channel_code=tranChannelCode AND glc.game_manufacturer_id=gameManufacturerId)
	ON DUPLICATE KEY UPDATE 
		lottery_transaction_type_id=VALUES(lottery_transaction_type_id), lottery_channel_id=VALUES(lottery_channel_id), transaction_time=VALUES(transaction_time),
		status=VALUES(status), lottery_transaction_idf=VALUES(lottery_transaction_idf);

	IF(tranTypeCode IN ('103','502')) THEN
		SELECT lottery_transaction_id INTO lotteryTranID
		FROM gaming_lottery_transactions WHERE lottery_transaction_idf=tranIDF;
	ELSE
		SET lotteryTranID=0;
	END IF;

	-- END Insert/Update Transaction

	-- Insert/Update Coupon
	INSERT INTO gaming_lottery_coupons (lottery_coupon_idf, game_manufacturer_id, client_stat_id, discount, promotions, coupon_date,coupon_cost, cancel_date, 
		lottery_coupon_status_id, lottery_coupon_type_id, lottery_transaction_id, lottery_wager_status_id,lottery_retailer_id, lottery_retailer_terminal_id, 
		lottery_retailer_employee_id,num_games, num_tickets, num_ticket_entries, num_participations, num_draws, display_name, is_active,
		win_gross_amount, win_net_amount, win_tax_amount, win_amount, client_loyalty_card_number_id,lottery_subscription_id)
	SELECT IF(tranTypeCode = '103',tranIDF,couponIDF) , gameManufacturerId, clientStatId, discount, promotions, couponDate, couponCost, cancelDate, glcs.lottery_coupon_status_id, 
		   glct.lottery_coupon_type_id, lotteryTranID, wager_status.lottery_wager_status_id, retailer.lottery_retailer_id, terminal.lottery_retailer_terminal_id,
		   employee.lottery_retailer_employee_id, numGames, numTickets, numTicketEntries, numParticipations, numParticipations, displayName, 1, winGross, 
		   winNet, winTax, winAmount, loyalty_card.client_loyalty_card_number_id, lotterySubscriptionId
	FROM gaming_lottery_coupon_statuses glcs 
	STRAIGHT_JOIN gaming_lottery_coupon_types glct ON (glcs.status_code=couponStatusCode AND glcs.game_manufacturer_id=gameManufacturerId) AND glct.coupon_type_code=coupontypeCode
	STRAIGHT_JOIN gaming_lottery_wager_statuses AS wager_status ON wager_status.name=wagerStatus
	LEFT JOIN gaming_client_loyalty_cards AS loyalty_card ON loyalty_card.card_number=loyaltyCardNumber AND loyalty_card.client_id=clientID
	LEFT JOIN gaming_lottery_retailers AS retailer ON retailer.retailer_idf=retailerIDF AND retailer.game_manufacturer_id=gameManufacturerId
	LEFT JOIN gaming_lottery_retailer_terminals AS terminal ON terminal.terminal_idf=terminalIDF AND terminal.game_manufacturer_id=gameManufacturerId
	LEFT JOIN gaming_lottery_retailer_employees AS employee ON employee.employee_idf=employeeIDF AND employee.game_manufacturer_id=gameManufacturerId
	ON DUPLICATE KEY UPDATE 
		lottery_coupon_idf=couponIDF, discount=VALUES(discount), promotions=VALUES(promotions), coupon_date=VALUES(coupon_date), 
		coupon_cost=VALUES(coupon_cost), cancel_date=VALUES(cancel_date), lottery_coupon_status_id=VALUES(lottery_coupon_status_id), 
		lottery_coupon_type_id=VALUES(lottery_coupon_type_id), lottery_transaction_id=VALUES(lottery_transaction_id), is_active=VALUES(is_active), 
		win_gross_amount=VALUES(win_gross_amount), win_net_amount=VALUES(win_net_amount), win_tax_amount=VALUES(win_tax_amount), win_amount=VALUES(win_amount); 

	SET couponID=LAST_INSERT_ID();

	-- Brian
	INSERT INTO gaming_lottery_coupon_games (lottery_coupon_id, game_id, order_num) VALUES (couponID, 21000000, 1) ON DUPLICATE KEY UPDATE order_num=order_num;

	INSERT INTO gaming_lottery_dbg_tickets (lottery_coupon_id, game_manufacturer_id, multi_draws, game_state_idf, first_draw_number, last_draw_number,
		promo_code_idf, advance_draws, extra_flag, robot_last_draw_number_sent, robot_offset_from_interval_minutes, robot_jackpot_min_value, ticket_cost, 
		num_ticket_entries, num_participations, selection_source, game_type, multiplier,is_primary_game,game_id)
	SELECT couponID, gameManufacturerId, multi_draws, game_state_idf, first_draw_number, last_draw_number,
			promo_code_idf, advance_draws, extra_flag, robot_last_draw_number_sent, robot_offset_from_interval_minutes, robot_jackpot_min_value, ticket_cost, num_ticket_entries, num_participations,
			selection_source, game_type, multiplier, is_primary, gaming_games.game_id
	FROM gaming_lottery_temporary_tickets tt FORCE INDEX (`INDEX`)
	STRAIGHT_JOIN gaming_games FORCE INDEX (manufacturer_game_idf) ON tt.game_state_idf = gaming_games.manufacturer_game_idf and gaming_games.game_manufacturer_id=gameManufacturerId
	WHERE tt.lottery_transaction_idf=tranIDF
	ON DUPLICATE KEY UPDATE 
		multi_draws=VALUES(multi_draws), game_state_idf=VALUES(game_state_idf), first_draw_number=VALUES(first_draw_number), last_draw_number=VALUES(last_draw_number),
		promo_code_idf=VALUES(promo_code_idf), advance_draws=VALUES(advance_draws), extra_flag=VALUES(extra_flag), 
		robot_last_draw_number_sent=VALUES(robot_last_draw_number_sent), robot_offset_from_interval_minutes=VALUES(robot_offset_from_interval_minutes), robot_jackpot_min_value=VALUES(robot_jackpot_min_value),
		num_ticket_entries=VALUES(num_ticket_entries), num_participations=VALUES(num_participations), 
		selection_source=VALUES(selection_source), game_type=VALUES(game_type), multiplier=VALUES(multiplier);

	INSERT INTO gaming_lottery_dbg_ticket_entries (lottery_dbg_ticket_id, topup, quick_numbers, quick_jokers, group_name, group_multiplier, numbers, jokers, extra_numbers,
		group_number, system_selection, selection_source, game_type, multiplier, quickpick_selection)
	SELECT glt.lottery_dbg_ticket_id, tte.topup, tte.quick_numbers, tte.quick_jokers, tte.group_name, group_multiplier, tte.numbers, tte.jokers, tte.extra_numbers,
		tte.group_number, tte.system_selection, tte.selection_source, tte.game_type, tte.multiplier, tte.quickpick_selection
	FROM gaming_lottery_temporary_ticket_entries tte FORCE INDEX (`INDEX`)
	STRAIGHT_JOIN gaming_games gg FORCE INDEX (manufacturer_game_idf) ON tte.game_state_idf = gg.manufacturer_game_idf and gg.game_manufacturer_id=gameManufacturerId
	STRAIGHT_JOIN gaming_lottery_dbg_tickets glt FORCE INDEX (lottery_coupon_id) ON glt.lottery_coupon_id=couponID AND glt.game_id=gg.game_id
	WHERE tte.lottery_transaction_idf=tranIDF
	ON DUPLICATE KEY UPDATE lottery_dbg_ticket_entry_id=LAST_INSERT_ID(lottery_dbg_ticket_entry_id), 
	  topup=VALUES(topup), quick_numbers=VALUES(quick_numbers), quick_jokers=VALUES(quick_jokers), group_name=VALUES(group_name), group_multiplier=VALUES(group_multiplier), numbers=VALUES(numbers), jokers=VALUES(jokers), extra_numbers=VALUES(extra_numbers),
	  group_number=VALUES(group_number), system_selection=VALUES(system_selection), selection_source=VALUES(selection_source), game_type=VALUES(game_type), multiplier=VALUES(multiplier), quickpick_selection=VALUES(quickpick_selection);

	INSERT INTO gaming_lottery_dbg_ticket_entry_boards (
	  lottery_dbg_ticket_entry_id, board_idf, numbers, board_type_idf, quickpick_selection)
	SELECT glte.lottery_dbg_ticket_entry_id, tteb.board_idf, tteb.numbers, tteb.board_type_idf, tteb.quickpick_selection
	FROM gaming_lottery_temporary_ticket_entry_boards tteb FORCE INDEX (`INDEX`)
	STRAIGHT_JOIN gaming_games gg FORCE INDEX (manufacturer_game_idf) ON tteb.game_state_idf = gg.manufacturer_game_idf and gg.game_manufacturer_id=gameManufacturerId
	STRAIGHT_JOIN gaming_lottery_dbg_tickets glt FORCE INDEX (lottery_coupon_id) ON glt.lottery_coupon_id=couponID AND glt.game_id=gg.game_id
	STRAIGHT_JOIN gaming_lottery_dbg_ticket_entries glte FORCE INDEX (unique_ticket_group_number) ON glte.lottery_dbg_ticket_id=glt.lottery_dbg_ticket_id AND glte.group_number=tteb.group_number
	WHERE tteb.lottery_transaction_idf=tranIDF
	ON DUPLICATE KEY UPDATE lottery_dbg_ticket_entry_board_id=LAST_INSERT_ID(lottery_dbg_ticket_entry_board_id),
	  board_idf=VALUES(board_idf), numbers=VALUES(numbers), board_type_idf=VALUES(board_type_idf), quickpick_selection=VALUES(quickpick_selection);
		
	CALL LotteryCreateParticipations(couponID);
/*
	INSERT INTO gaming_lottery_participations (lottery_draw_id,lottery_dbg_ticket_id,sort_order,game_state_idf,draw_number,participation_idf,
			draw_offset,draw_date,participation_cost,game_manufacturer_id,lottery_participation_status_id,lottery_wager_status_id)
	SELECT 
		gld.lottery_draw_id, glt.lottery_dbg_ticket_id, ttp.sort_order, ttp.game_state_idf, ttp.draw_number, ttp.participation_idf, 
		ttp.draw_offset, ttp.draw_date, ttp.participation_cost, gameManufacturerId, glps.lottery_participation_status_id, glws.lottery_wager_status_id
	FROM gaming_lottery_temporary_ticket_participations ttp FORCE INDEX (`INDEX`)
	STRAIGHT_JOIN gaming_lottery_participation_statuses glps ON glps.status_code=ttp.status_code AND glps.game_manufacturer_id = gameManufacturerId
	STRAIGHT_JOIN gaming_lottery_wager_statuses AS glws ON glws.name = ttp.wager_status
	STRAIGHT_JOIN gaming_games gg FORCE INDEX (manufacturer_game_idf) ON ttp.game_state_idf = gg.manufacturer_game_idf AND gg.game_manufacturer_id = gameManufacturerId
	STRAIGHT_JOIN gaming_lottery_dbg_tickets glt FORCE INDEX (lottery_coupon_id) ON glt.lottery_coupon_id=couponID AND glt.game_id=gg.game_id
	LEFT JOIN gaming_lottery_draws AS gld FORCE INDEX (game_draw_number) ON gld.draw_number = ttp.draw_number AND gld.game_id=gg.game_id
	WHERE ttp.lottery_transaction_idf=tranIDF
	ON DUPLICATE KEY UPDATE 
		gaming_lottery_participations.game_state_idf=VALUES(game_state_idf), 
		gaming_lottery_participations.draw_number=VALUES(draw_number), 
		gaming_lottery_participations.participation_idf=VALUES(participation_idf), 
		gaming_lottery_participations.draw_offset=VALUES(draw_offset), 
		gaming_lottery_participations.draw_date=VALUES(draw_date), 
		gaming_lottery_participations.lottery_participation_status_id=VALUES(lottery_participation_status_id);
*/
	
	-- TODO update promotions
	
	DELETE gaming_lottery_temporary_tickets FROM gaming_lottery_temporary_tickets FORCE INDEX (`INDEX`) WHERE lottery_transaction_idf=tranIDF;
	DELETE gaming_lottery_temporary_ticket_entries FROM gaming_lottery_temporary_ticket_entries FORCE INDEX (`INDEX`)  WHERE lottery_transaction_idf=tranIDF ;
	DELETE gaming_lottery_temporary_ticket_entry_boards FROM gaming_lottery_temporary_ticket_entry_boards FORCE INDEX (`INDEX`)  WHERE lottery_transaction_idf=tranIDF ;
	
    -- DELETE gaming_lottery_temporary_ticket_participations FROM gaming_lottery_temporary_ticket_participations FORCE INDEX (`INDEX`)  WHERE lottery_transaction_idf=tranIDF;

END$$

DELIMITER ;

