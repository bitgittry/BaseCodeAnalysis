DROP procedure IF EXISTS `PlayProcessBetsUpdatePromotionStatusesOnBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayProcessBetsUpdatePromotionStatusesOnBet`(gamePlayProcessCounterID BIGINT)
root: BEGIN

  -- Sports Optimization
  -- Lottery Addition
  -- Removed AND condition on gaming_promotions.calculate_on_bet when checking the promotino with the highest priority 

  DECLARE promotionAwardPrizeOnAchievementEnabled, singlePromotionsEnabled, noMoreRecords TINYINT(1) DEFAULT 0;
  DECLARE contributeAllowMultiple, contributeRealMoneyOnly, sportsBookActive, lottoActive TINYINT(1) DEFAULT 0;
  DECLARE onBetTakesPrecedenced TINYINT(1) DEFAULT 0;
  DECLARE dateTimeNow DATETIME DEFAULT NOW();

  DECLARE promotionID, promotionGetCounterID, promotionRecurrenceID BIGINT DEFAULT -1;
  
  DECLARE promotionAwardOnAchievementCursor CURSOR FOR 
    SELECT pps.promotion_id, IFNULL(pps.promotion_recurrence_date_id, 0) 
    FROM gaming_game_rounds_promotion_contributions AS promotion_contributions
    JOIN gaming_promotions_player_statuses AS pps ON
      promotion_contributions.game_play_process_counter_id=gamePlayProcessCounterID AND
      promotion_contributions.promotion_player_status_id=pps.promotion_player_status_id AND
      (pps.requirement_achieved=1 AND pps.has_awarded_bonus=0)
    JOIN gaming_promotions ON pps.promotion_id=gaming_promotions.promotion_id AND gaming_promotions.is_active=1 AND 
      gaming_promotions.is_single=0 AND 
	  (gaming_promotions.award_prize_on_achievement=1 OR gaming_promotions.award_prize_timing_type = 1) AND 
	  (award_num_players=0 OR num_players_awarded<award_num_players) AND 
	  gaming_promotions.promotion_achievement_type_id NOT IN (5)
	LEFT JOIN gaming_promotions_recurrence_dates dates ON dates.promotion_recurrence_date_id = pps.promotion_recurrence_date_id 
	WHERE (IFNULL(gaming_promotions.award_num_players_per_occurence, 9999999999) > IFNULL(dates.awarded_prize_count, 0))
    GROUP BY pps.promotion_id, IFNULL(pps.promotion_recurrence_date_id, 0);

  DECLARE promotionAwardSingleCursor CURSOR FOR 
    SELECT pps.promotion_id, IFNULL(pps.promotion_recurrence_date_id, 0) 
    FROM gaming_game_rounds_promotion_contributions AS promotion_contributions
    JOIN gaming_promotions_player_statuses AS pps ON
      promotion_contributions.game_play_process_counter_id=gamePlayProcessCounterID AND
      promotion_contributions.promotion_player_status_id=pps.promotion_player_status_id
    JOIN gaming_promotions ON pps.promotion_id=gaming_promotions.promotion_id AND gaming_promotions.is_active=1 AND 
      gaming_promotions.is_single=1 AND (award_num_players=0 OR num_players_awarded<=award_num_players) AND gaming_promotions.promotion_achievement_type_id IN (1,2)
      AND (gaming_promotions.award_prize_on_achievement=1 OR gaming_promotions.award_prize_timing_type = 1) 
      AND (gaming_promotions.single_prize_per_transaction OR (pps.requirement_achieved=1 AND pps.has_awarded_bonus=0))
	LEFT JOIN gaming_promotions_recurrence_dates dates ON dates.promotion_recurrence_date_id = pps.promotion_recurrence_date_id 
	WHERE (IFNULL(gaming_promotions.award_num_players_per_occurence, 9999999999) >= IFNULL(dates.awarded_prize_count, 0))
	AND pps.achieved_amount!=pps.single_achieved_amount_awarded
	GROUP BY pps.promotion_id, IFNULL(pps.promotion_recurrence_date_id, 0);

  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;
        
  -- only process if gaming_promotions.calculate_on_bet is true
	SET @gamePlayProcessCounterID = gamePlayProcessCounterID;
	SELECT value_bool INTO contributeAllowMultiple FROM gaming_settings WHERE name='PROMOTION_ROUND_CONTRIBUTION_ALLOW_MULTIPLE'; 
	SELECT value_bool INTO contributeRealMoneyOnly FROM gaming_settings WHERE name='PROMOTION_CONTRIBUTION_REAL_MONEY_ONLY'; 
	SELECT value_bool INTO sportsBookActive FROM gaming_settings WHERE name='SPORTSBOOK_ACTIVE'; 
	SELECT value_bool INTO onBetTakesPrecedenced FROM gaming_settings WHERE name='PROMOTION_ON_BET_TAKES_PRECEDENCE'; 
	SELECT value_bool INTO singlePromotionsEnabled FROM gaming_settings WHERE name='PROMOTION_SINGLE_PROMOS_ENABLED';
	SELECT value_bool INTO lottoActive FROM gaming_settings WHERE name='LOTTO_ACTIVE'; 

	SET @round_row_count=1;
	SET @game_round_id=-1;
	SET @max_contributions_per_round=IF(contributeAllowMultiple, 10, 1); 
  

	INSERT INTO gaming_promotion_get_counter (date_added) VALUES (NOW());
	SET promotionGetCounterID=LAST_INSERT_ID();

-- UPDATE THE CURRENT OCCURENCE TO FALSE
	UPDATE gaming_game_plays_process_counter_bets 
	JOIN gaming_game_plays ON
		gaming_game_plays_process_counter_bets.game_play_process_counter_id=@gamePlayProcessCounterID AND
		gaming_game_plays_process_counter_bets.game_play_id=gaming_game_plays.game_play_id AND gaming_game_plays.payment_transaction_type_id=12 
	JOIN gaming_promotions_player_statuses AS gpps FORCE INDEX (client_open_promos) ON 
		gpps.client_stat_id=gaming_game_plays.client_stat_id AND gpps.is_active=1 AND gpps.is_current=1 AND gpps.end_date<dateTimeNow
	JOIN gaming_promotions ON gpps.promotion_id=gaming_promotions.promotion_id AND gaming_promotions.recurrence_enabled
	LEFT JOIN gaming_promotions_recurrence_dates AS recurrence_dates FORCE INDEX (promotion_active_current) ON 
		recurrence_dates.promotion_id=gaming_promotions.promotion_id AND recurrence_dates.is_active=1 AND recurrence_dates.is_current=1 
	SET gpps.is_current=0 
	WHERE (recurrence_dates.promotion_recurrence_date_id IS NULL OR gpps.promotion_recurrence_date_id!=recurrence_dates.promotion_recurrence_date_id);

 -- INSERT AND SET THE NEW OCCURENCE TO CURRENT
	INSERT INTO gaming_promotions_player_statuses (promotion_id, child_promotion_id, client_stat_id, priority, opted_in_date, currency_id, creation_counter_id, promotion_recurrence_date_id, start_date, end_date)
	SELECT gaming_promotions.promotion_id, child_promotion.promotion_id, gaming_game_plays.client_stat_id, gaming_promotions.priority, NOW(), gcs.currency_id, promotionGetCounterID,
		recurrence_dates.promotion_recurrence_date_id, IFNULL(recurrence_dates.start_date, gaming_promotions.achievement_start_date), IFNULL(recurrence_dates.end_date, gaming_promotions.achievement_end_date)
	FROM gaming_game_plays_process_counter_bets 
	JOIN gaming_game_plays ON
		gaming_game_plays_process_counter_bets.game_play_process_counter_id=@gamePlayProcessCounterID AND
		gaming_game_plays_process_counter_bets.game_play_id=gaming_game_plays.game_play_id AND gaming_game_plays.payment_transaction_type_id=12 
	JOIN gaming_promotions ON gaming_promotions.is_active=1 AND gaming_promotions.recurrence_enabled =1
	JOIN gaming_promotions_players_opted_in AS gppo ON gppo.promotion_id = gaming_promotions.promotion_id 
		AND gppo.client_stat_id = gaming_game_plays.client_stat_id AND gppo.opted_in = 1 AND gppo.awarded_prize_count < IFNULL(gaming_promotions.award_num_times_per_player, 99999999999)
	JOIN gaming_promotions_recurrence_dates AS recurrence_dates FORCE INDEX (promotion_active_current) ON 
		recurrence_dates.promotion_id=gaming_promotions.promotion_id AND recurrence_dates.is_active=1 AND recurrence_dates.is_current=1 
		AND (recurrence_dates.awarded_prize_count < IFNULL(gaming_promotions.award_num_players_per_occurence, 99999999999))
	JOIN gaming_client_stats AS gcs ON gcs.client_stat_id = gaming_game_plays.client_stat_id AND gcs.is_active=1
	LEFT JOIN gaming_player_selections_player_cache AS CS ON CS.client_stat_id=gaming_game_plays.client_stat_id AND gaming_promotions.player_selection_id = CS.player_selection_id
	LEFT JOIN gaming_promotions AS child_promotion ON child_promotion.parent_promotion_id=gaming_promotions.promotion_id AND child_promotion.is_current=1
	LEFT JOIN gaming_promotions_player_statuses AS gpps ON gpps.promotion_id=gaming_promotions.promotion_id AND gpps.client_stat_id=gaming_game_plays.client_stat_id AND gpps.is_current=1
	WHERE (gaming_promotions.achievement_end_date>=NOW() AND ((gaming_promotions.need_to_opt_in_flag=0 AND IFNULL(gppo.creation_counter_id,0)=promotionGetCounterID) 
		OR (gpps.client_stat_id IS NULL AND gppo.client_stat_id IS NOT NULL AND gppo.opted_in = 1 AND 
		(gaming_promotions.auto_opt_in_next = 1 OR (gaming_promotions.auto_opt_in_next = 0 AND gaming_promotions.need_to_opt_in_flag = 0)))) AND 
		(gaming_promotions.can_opt_in=1 AND gaming_promotions.num_players_opted_in<gaming_promotions.max_players)) 
		AND (IFNULL(CS.player_in_selection, PlayerSelectionIsPlayerInSelectionCached(gaming_promotions.player_selection_id, gaming_game_plays.client_stat_id))=1 OR gaming_promotions.auto_opt_in_next = 1)
		AND gpps.promotion_player_status_id IS NULL ;

 -- CASINO --
	INSERT INTO gaming_game_rounds_promotion_contributions(game_round_id, promotion_id, timestamp, promotion_player_status_id, promotion_player_status_day_id, promotion_wgr_req_weight, bet, win, loss, game_play_process_counter_id)
	SELECT game_round_id, promotion_id, NOW(), promotion_player_status_id, promotion_player_status_day_id, promotion_wgr_req_weight, bet_total, win_total, loss_total, @gamePlayProcessCounterID
	FROM 
	(
		SELECT PP.*, @round_row_count:=IF(game_round_id!=@game_round_id, 1, @round_row_count+1) AS round_row_count, @game_round_id:=IF(game_round_id!=@game_round_id, game_round_id, @game_round_id)
		FROM
		(
			SELECT gaming_game_rounds.game_round_id, pps.promotion_id, pps.promotion_player_status_id, ppsd.promotion_player_status_day_id, gaming_promotions_games.promotion_wgr_req_weight, gaming_promotions_achievement_types.name AS promotion_type, gaming_promotions.calculate_on_bet,
				LEAST(IFNULL(wager_restrictions.max_wager_contibution, 1000000000000), LEAST(IFNULL(wager_restrictions.max_wager_contibution_before_weight, 1000000000000), IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, bet_real, bet_total))*gaming_promotions_games.promotion_wgr_req_weight, IF(gaming_promotions.is_single AND gaming_promotions_achievement_types.name='Bet'AND gppa.max_cap IS NOT NULL, gppa.max_cap, 1000000000000)) AS bet_total, 
				0 AS win_total, 
				0 AS loss_total
			FROM gaming_game_plays_process_counter_bets 
			JOIN gaming_game_plays ON
				gaming_game_plays_process_counter_bets.game_play_process_counter_id=@gamePlayProcessCounterID AND
				gaming_game_plays_process_counter_bets.game_play_id=gaming_game_plays.game_play_id AND gaming_game_plays.payment_transaction_type_id IN (12, 20) 
			JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id AND gaming_game_rounds.game_round_type_id=1 
			JOIN gaming_promotions ON gaming_promotions.is_active=1 AND (gaming_game_rounds.date_time_start BETWEEN achievement_start_date AND achievement_end_date)
					-- AND  gaming_promotions.calculate_on_bet -- This needs to be removed since we want to join with the other promotions and check that the promotion with calculate on bet has the highest priority
			JOIN gaming_promotions_achievement_types ON 
				gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
			JOIN gaming_promotions_player_statuses AS pps FORCE INDEX (promotion_client_active_current) ON
				(pps.promotion_id=gaming_promotions.promotion_id AND
				pps.client_stat_id=gaming_game_rounds.client_stat_id AND pps.is_active=1 AND pps.is_current = 1 AND (IF(gaming_promotions.recurrence_enabled = 1, (gaming_game_rounds.date_time_start BETWEEN pps.start_date AND pps.end_date), 1=1)))
			JOIN gaming_promotions_games ON 
				gaming_promotions.promotion_id=gaming_promotions_games.promotion_id AND
				gaming_game_rounds.operator_game_id=gaming_promotions_games.operator_game_id
			LEFT JOIN gaming_promotions_achievement_amounts ON
				gaming_promotions.promotion_id=gaming_promotions_achievement_amounts.promotion_id AND
				pps.currency_id=gaming_promotions_achievement_amounts.currency_id AND
				(gaming_promotions.is_single=0 OR ( 
				(gaming_promotions.promotion_achievement_type_id=1 AND (IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, bet_real, bet_total)*gaming_promotions_games.promotion_wgr_req_weight)>=gaming_promotions_achievement_amounts.amount)

				))
			LEFT JOIN gaming_promotions_achievement_rounds ON
				gaming_promotions.promotion_id=gaming_promotions_achievement_rounds.promotion_id AND
				pps.currency_id=gaming_promotions_achievement_rounds.currency_id
			LEFT JOIN gaming_promotions_status_days ON
				gaming_promotions.promotion_id=gaming_promotions_status_days.promotion_id AND (DATE(gaming_game_rounds.date_time_start)=gaming_promotions_status_days.day_start_time)    
			LEFT JOIN gaming_promotions_player_statuses_daily AS ppsd ON
				pps.promotion_player_status_id=ppsd.promotion_player_status_id AND
				gaming_promotions_status_days.promotion_status_day_id=ppsd.promotion_status_day_id
			LEFT JOIN gaming_promotion_wager_restrictions AS wager_restrictions ON
				wager_restrictions.promotion_id=gaming_promotions.promotion_id AND
				wager_restrictions.currency_id=pps.currency_id
			LEFT JOIN gaming_promotions_prize_amounts AS gppa ON
				gaming_promotions.promotion_id=gppa.promotion_id AND pps.currency_id=gppa.currency_id 
			WHERE
				(singlePromotionsEnabled OR gaming_promotions.is_single=0) AND
				(gaming_promotions_games.promotion_id IS NOT NULL) AND 

				(pps.promotion_recurrence_date_id IS NULL OR
				(gaming_promotions_status_days.promotion_recurrence_date_id IS NULL OR 
					(pps.promotion_recurrence_date_id=gaming_promotions_status_days.promotion_recurrence_date_id))) AND

				((gaming_promotions_achievement_types.is_amount_achievement AND gaming_promotions_achievement_amounts.promotion_id IS NOT NULL) OR 
				(gaming_promotions_achievement_types.is_round_achievement AND gaming_promotions_achievement_rounds.promotion_id IS NOT NULL AND 
				IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, gaming_game_rounds.bet_real, gaming_game_rounds.bet_total)>=gaming_promotions_achievement_rounds.min_bet_amount) 
				) AND pps.requirement_achieved=0 AND IFNULL(ppsd.daily_requirement_achieved, 0)=0
			ORDER BY gaming_game_rounds.game_round_id, IF(onBetTakesPrecedenced AND gaming_promotions_achievement_types.name='Bet', pps.priority-1000, pps.priority) ASC, pps.opted_in_date DESC 
		) AS PP
	) AS PP
	WHERE PP.promotion_type='BET' AND PP.calculate_on_bet AND round_row_count<=@max_contributions_per_round
	GROUP BY game_round_id, promotion_player_status_id
	ON DUPLICATE KEY UPDATE 
		promotion_player_status_day_id=VALUES(promotion_player_status_day_id), 
        promotion_wgr_req_weight=VALUES(promotion_wgr_req_weight), 
        bet=VALUES(bet)-bet, 
        win=VALUES(win)-win, 
        loss=VALUES(loss)-loss, 
        game_play_process_counter_id=VALUES(game_play_process_counter_id); 

	IF (lottoActive) THEN
    
		SET @round_row_count=1;
		SET @game_round_id=-1;
		SET @max_contributions_per_round=IF(contributeAllowMultiple, 10, 1); 
				
		INSERT INTO gaming_game_rounds_promotion_contributions(game_round_id, promotion_id, timestamp, promotion_player_status_id, promotion_player_status_day_id, promotion_wgr_req_weight, bet, win, loss, game_play_process_counter_id)
		SELECT game_round_id, promotion_id, NOW(), promotion_player_status_id, promotion_player_status_day_id, promotion_wgr_req_weight, bet_total, win_total, loss_total, @gamePlayProcessCounterID
		FROM 
		(
			SELECT PP.*, @round_row_count:=IF(game_round_id!=@game_round_id, 1, @round_row_count+1) AS round_row_count, @game_round_id:=IF(game_round_id!=@game_round_id, game_round_id, @game_round_id)
			FROM
			(
				SELECT gaming_game_rounds.game_round_id, pps.promotion_id, pps.promotion_player_status_id, ppsd.promotion_player_status_day_id, gaming_promotions_games.promotion_wgr_req_weight, gaming_promotions_achievement_types.name AS promotion_type, gaming_promotions.calculate_on_bet,
					LEAST(IFNULL(wager_restrictions.max_wager_contibution, 1000000000000), LEAST(IFNULL(wager_restrictions.max_wager_contibution_before_weight, 1000000000000), IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only,  gaming_game_rounds.bet_real,  gaming_game_rounds.bet_total))*gaming_promotions_games.promotion_wgr_req_weight, IF(gaming_promotions.is_single AND gaming_promotions_achievement_types.name='Bet'AND gppa.max_cap IS NOT NULL, gppa.max_cap, 1000000000000)) AS bet_total, 
					0 AS win_total, 
					0 AS loss_total
				FROM gaming_game_plays_process_counter_bets 
				JOIN gaming_game_plays ON
					gaming_game_plays_process_counter_bets.game_play_process_counter_id=@gamePlayProcessCounterID AND
					gaming_game_plays_process_counter_bets.game_play_id=gaming_game_plays.game_play_id AND gaming_game_plays.payment_transaction_type_id IN (12, 20) 
				JOIN gaming_game_rounds AS bet_round ON gaming_game_plays.game_round_id=bet_round.game_round_id AND bet_round.game_round_type_id=7 
				JOIN gaming_game_rounds_lottery AS parent_round ON parent_round.game_round_id = bet_round.game_round_id AND is_parent_round=1
				JOIN gaming_game_rounds_lottery AS child_round ON child_round.parent_game_round_id = parent_round.game_round_id
				JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id = child_round.game_round_id
				JOIN gaming_promotions ON gaming_promotions.is_active=1 AND (gaming_game_rounds.date_time_start BETWEEN achievement_start_date AND achievement_end_date)
					-- AND  gaming_promotions.calculate_on_bet -- This needs to be removed since we want to join with the other promotions and check that the promotion with calculate on bet has the highest priority
				JOIN gaming_promotions_achievement_types ON 
					gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
				JOIN gaming_promotions_player_statuses AS pps FORCE INDEX (promotion_client_active_current) ON
					(pps.promotion_id=gaming_promotions.promotion_id AND
					pps.client_stat_id=gaming_game_rounds.client_stat_id AND pps.is_active=1 AND pps.is_current = 1  AND (IF(gaming_promotions.recurrence_enabled = 1, (gaming_game_rounds.date_time_start BETWEEN pps.start_date AND pps.end_date), 1=1)))
				JOIN gaming_promotions_games ON 
					gaming_promotions.promotion_id=gaming_promotions_games.promotion_id AND
					gaming_game_rounds.operator_game_id=gaming_promotions_games.operator_game_id
				LEFT JOIN gaming_promotions_achievement_amounts ON
					gaming_promotions.promotion_id=gaming_promotions_achievement_amounts.promotion_id AND
					pps.currency_id=gaming_promotions_achievement_amounts.currency_id AND
					(gaming_promotions.is_single=0 OR 
						( 
							gaming_promotions.promotion_achievement_type_id=1 AND 
								(
									IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only,  gaming_game_rounds.bet_real,  gaming_game_rounds.bet_total)
									*gaming_promotions_games.promotion_wgr_req_weight
								) >=gaming_promotions_achievement_amounts.amount
						)
                    )
				LEFT JOIN gaming_promotions_achievement_rounds ON
					gaming_promotions.promotion_id=gaming_promotions_achievement_rounds.promotion_id AND
					pps.currency_id=gaming_promotions_achievement_rounds.currency_id
				LEFT JOIN gaming_promotions_status_days ON
					gaming_promotions.promotion_id=gaming_promotions_status_days.promotion_id AND (DATE(gaming_game_rounds.date_time_start)=gaming_promotions_status_days.day_start_time)    
				LEFT JOIN gaming_promotions_player_statuses_daily AS ppsd ON
					pps.promotion_player_status_id=ppsd.promotion_player_status_id AND
					gaming_promotions_status_days.promotion_status_day_id=ppsd.promotion_status_day_id
				LEFT JOIN gaming_promotion_wager_restrictions AS wager_restrictions ON
					wager_restrictions.promotion_id=gaming_promotions.promotion_id AND
					wager_restrictions.currency_id=pps.currency_id
				LEFT JOIN gaming_promotions_prize_amounts AS gppa ON
					gaming_promotions.promotion_id=gppa.promotion_id AND pps.currency_id=gppa.currency_id 
				WHERE
					(singlePromotionsEnabled OR gaming_promotions.is_single=0) AND
					(gaming_promotions_games.promotion_id IS NOT NULL) AND 
					(pps.promotion_recurrence_date_id IS NULL OR
					(gaming_promotions_status_days.promotion_recurrence_date_id IS NULL OR (pps.promotion_recurrence_date_id=gaming_promotions_status_days.promotion_recurrence_date_id))) AND
					((gaming_promotions_achievement_types.is_amount_achievement AND gaming_promotions_achievement_amounts.promotion_id IS NOT NULL) OR 
					(gaming_promotions_achievement_types.is_round_achievement AND gaming_promotions_achievement_rounds.promotion_id IS NOT NULL AND 
					IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, gaming_game_rounds.bet_real, gaming_game_rounds.bet_total)>=gaming_promotions_achievement_rounds.min_bet_amount) 
					) AND pps.requirement_achieved=0 AND IFNULL(ppsd.daily_requirement_achieved, 0)=0
				ORDER BY gaming_game_rounds.game_round_id, IF(onBetTakesPrecedenced AND gaming_promotions_achievement_types.name='Bet', pps.priority-1000, pps.priority) ASC, pps.opted_in_date DESC 
			) AS PP
		) AS PP
		WHERE PP.promotion_type='BET' AND PP.calculate_on_bet AND round_row_count<=@max_contributions_per_round
		GROUP BY game_round_id, promotion_player_status_id
		ON DUPLICATE KEY UPDATE 
			promotion_player_status_day_id=VALUES(promotion_player_status_day_id), 
			promotion_wgr_req_weight=VALUES(promotion_wgr_req_weight), 
			bet=VALUES(bet)-bet, 
			win=VALUES(win)-win, 
			loss=VALUES(loss)-loss, 
			game_play_process_counter_id=VALUES(game_play_process_counter_id);   

	END IF;
    
  
  IF (sportsBookActive) THEN
    SET @round_row_count = 1;
    SET @game_round_id = -1;
    SET @max_contributions_per_round = IF(contributeAllowMultiple, 10, 1); 
  
    INSERT INTO gaming_game_rounds_promotion_contributions (game_round_id, promotion_id, timestamp, promotion_player_status_id, promotion_player_status_day_id, promotion_wgr_req_weight, bet, win, loss, game_play_process_counter_id)
    SELECT game_round_id, promotion_id, NOW(), promotion_player_status_id, promotion_player_status_day_id, promotion_wgr_req_weight, bet_total, win_total, loss_total, @gamePlayProcessCounterID
    FROM 
    (
      SELECT PP.*, 
        @round_row_count:=IF(game_round_id!=@game_round_id, 1, @round_row_count+1) AS round_row_count, 
        @game_round_id:=IF(game_round_id!=@game_round_id, game_round_id, @game_round_id)
      FROM
      (
        SELECT gaming_game_rounds.game_round_id, pps.promotion_id, pps.promotion_player_status_id, ppsd.promotion_player_status_day_id, 
            IF(sb_weights.weight IS NULL OR sb_weights_multiple.weight IS NULL, 
                COALESCE(sb_weights.weight, sb_weights_multiple.weight), 
                LEAST(sb_weights.weight, sb_weights_multiple.weight)
              ) AS promotion_wgr_req_weight, 
            gaming_promotions_achievement_types.name AS promotion_type,
            LEAST( IFNULL(wager_restrictions.max_wager_contibution, 10000000000), 
                   IF(gaming_promotions.is_single AND gaming_promotions_achievement_types.name='Bet' AND gppa.max_cap IS NOT NULL, gppa.max_cap, 1000000000000),
                   ( LEAST(IFNULL(wager_restrictions.max_wager_contibution_before_weight, 10000000000),
                           IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, bet_real, bet_total)) * 
                     IF(sb_weights.weight IS NULL OR sb_weights_multiple.weight IS NULL, 
                        COALESCE(sb_weights.weight, sb_weights_multiple.weight), 
                        LEAST(sb_weights.weight, sb_weights_multiple.weight)
                       )
                   )
                 ) AS bet_total, 
            0 AS win_total, 
            0 AS loss_total
        FROM gaming_game_plays_process_counter_bets 
        JOIN gaming_game_plays ON
            gaming_game_plays_process_counter_bets.game_play_process_counter_id=@gamePlayProcessCounterID AND
            gaming_game_plays_process_counter_bets.game_play_id=gaming_game_plays.game_play_id AND
            gaming_game_plays.payment_transaction_type_id IN (12, 20) 
        JOIN gaming_game_rounds ON 
            gaming_game_rounds.sb_bet_id=gaming_game_plays.sb_bet_id AND 
            gaming_game_rounds.sb_extra_id IS NOT NULL AND 
            gaming_game_rounds.game_round_type_id IN (4,5) 
        JOIN gaming_promotions ON 
            gaming_promotions.is_active=1 AND 
            gaming_game_rounds.date_time_start BETWEEN achievement_start_date AND achievement_end_date AND
            NOT gaming_promotions.promotion_achievement_type_id = 5 
            -- AND  gaming_promotions.calculate_on_bet -- This needs to be removed since we want to join with the other promotions and check that the promotion with calculate on bet has the highest priority
        JOIN gaming_promotions_achievement_types ON 
            gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
        JOIN gaming_promotions_player_statuses AS pps FORCE INDEX (promotion_client_active_current) ON
            pps.promotion_id=gaming_promotions.promotion_id AND
            pps.client_stat_id=gaming_game_rounds.client_stat_id AND 
            pps.is_active=1 AND 
            pps.is_current = 1 AND 
            pps.requirement_achieved = 0 AND 
            IF(gaming_promotions.recurrence_enabled = 1, gaming_game_rounds.date_time_start BETWEEN pps.start_date AND pps.end_date, 1=1)
        LEFT JOIN  
        (
            SELECT ggr.game_round_id, crit.promotion_id, sing.odd, AVG(wght.weight) AS weight
            FROM gaming_game_plays_process_counter_bets AS ggppcb
            JOIN gaming_game_plays AS ggp ON 
                ggppcb.game_play_process_counter_id = @gamePlayProcessCounterID AND
                ggppcb.game_play_id = ggp.game_play_id AND 
                ggp.payment_transaction_type_id IN (12, 20) 
            JOIN gaming_game_rounds AS ggr ON
                ggr.sb_bet_id=ggp.sb_bet_id AND 
                ggr.sb_extra_id IS NOT NULL AND 
                ggr.game_round_type_id = 4           
            JOIN gaming_promotions AS promo ON 
                promo.is_active=1 AND 
                ggr.date_time_start BETWEEN promo.achievement_start_date AND promo.achievement_end_date AND 
                NOT promo.promotion_achievement_type_id = 5
            STRAIGHT_JOIN gaming_sb_bet_singles AS sing FORCE INDEX (sb_bet_id) ON 
                ggr.sb_bet_id=sing.sb_bet_id AND 
                ggr.sb_extra_id=sing.sb_selection_id
            STRAIGHT_JOIN gaming_sb_selections AS sel ON sing.sb_selection_id = sel.sb_selection_id
            STRAIGHT_JOIN gaming_promotions_wgr_sb_eligibility_criterias AS crit ON promo.promotion_id = crit.promotion_id
            STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel1 ON 
                crit.eligibility_criterias_id = wsel1.eligibility_criterias_id AND 
                wsel1.sb_entity_type_id = 1 AND 
                (wsel1.sb_entity_id IS NULL OR wsel1.sb_entity_id = sel.sb_sport_id)
            STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel2 ON 
                wsel1.eligibility_criterias_id = wsel2.eligibility_criterias_id AND 
                wsel2.sb_entity_type_id = 2 AND 
                (wsel2.sb_entity_id IS NULL OR wsel2.sb_entity_id = sel.sb_region_id) 
            STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel3 ON 
                wsel2.eligibility_criterias_id = wsel3.eligibility_criterias_id AND 
                wsel3.sb_entity_type_id = 3 AND 
                (wsel3.sb_entity_id IS NULL OR wsel3.sb_entity_id = sel.sb_group_id)
            STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel4 ON 
                wsel3.eligibility_criterias_id = wsel4.eligibility_criterias_id AND 
                wsel4.sb_entity_type_id = 4 AND 
                (wsel4.sb_entity_id IS NULL OR wsel4.sb_entity_id = sel.sb_event_id) 
            STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel5 ON 
                wsel4.eligibility_criterias_id = wsel5.eligibility_criterias_id AND 
                wsel5.sb_entity_type_id = 5 AND 
                (wsel5.sb_entity_id IS NULL OR wsel5.sb_entity_id = sel.sb_market_id)
            STRAIGHT_JOIN gaming_promotions_wgr_sb_weights AS wght ON 
                wsel5.eligibility_criterias_id = wght.eligibility_criterias_id
            WHERE sing.odd >= wght.min_odd AND (wght.max_odd IS NULL OR sing.odd < wght.max_odd)
            GROUP BY crit.promotion_id, ggr.game_round_id 
        ) AS sb_weights ON 
            gaming_game_rounds.game_round_id = sb_weights.game_round_id AND 
            gaming_promotions.promotion_id = sb_weights.promotion_id AND 
            pps.promotion_id = sb_weights.promotion_id AND
            (gaming_promotions.min_odd IS NULL OR sb_weights.odd >= gaming_promotions.min_odd)          
        LEFT JOIN
        (
            SELECT ggr.game_round_id, crit.promotion_id, mul.odd, AVG(wght.weight) AS weight
            FROM gaming_game_plays_process_counter_bets AS ggppcb
            JOIN gaming_game_plays AS ggp ON 
                ggppcb.game_play_process_counter_id = @gamePlayProcessCounterID AND
                ggppcb.game_play_id = ggp.game_play_id AND 
                ggp.payment_transaction_type_id IN (12, 20) 
            JOIN gaming_game_rounds AS ggr ON
                ggr.sb_bet_id=ggp.sb_bet_id AND 
                ggr.sb_extra_id IS NOT NULL AND 
                ggr.game_round_type_id = 5           
            JOIN gaming_promotions AS promo ON 
                promo.is_active=1 AND 
                ggr.date_time_start BETWEEN promo.achievement_start_date AND promo.achievement_end_date AND 
                NOT promo.promotion_achievement_type_id = 5
            STRAIGHT_JOIN gaming_sb_bet_multiples AS mul FORCE INDEX (sb_bet_id) ON 
                ggr.sb_bet_id = mul.sb_bet_id AND 
                ggr.sb_extra_id = mul.sb_multiple_type_id
            STRAIGHT_JOIN gaming_sb_bet_multiples_singles AS mulsin FORCE INDEX (sb_bet_multiple_id) ON mul.sb_bet_multiple_id = mulsin.sb_bet_multiple_id
            STRAIGHT_JOIN gaming_sb_selections AS sel ON mulsin.sb_selection_id = sel.sb_selection_id
            STRAIGHT_JOIN gaming_promotions_wgr_sb_eligibility_criterias AS crit ON promo.promotion_id = crit.promotion_id
            STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel1 ON 
                crit.eligibility_criterias_id = wsel1.eligibility_criterias_id AND 
                wsel1.sb_entity_type_id = 1 AND 
                (wsel1.sb_entity_id IS NULL OR wsel1.sb_entity_id = sel.sb_sport_id)
            STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel2 ON 
                wsel1.eligibility_criterias_id = wsel2.eligibility_criterias_id AND 
                wsel2.sb_entity_type_id = 2 AND 
                (wsel2.sb_entity_id IS NULL OR wsel2.sb_entity_id = sel.sb_region_id) 
            STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel3 ON 
                wsel2.eligibility_criterias_id = wsel3.eligibility_criterias_id AND 
                wsel3.sb_entity_type_id = 3 AND 
                (wsel3.sb_entity_id IS NULL OR wsel3.sb_entity_id = sel.sb_group_id)
            STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel4 ON 
                wsel3.eligibility_criterias_id = wsel4.eligibility_criterias_id AND 
                wsel4.sb_entity_type_id = 4 AND 
                (wsel4.sb_entity_id IS NULL OR wsel4.sb_entity_id = sel.sb_event_id) 
            STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel5 ON 
                wsel4.eligibility_criterias_id = wsel5.eligibility_criterias_id AND 
                wsel5.sb_entity_type_id = 5 AND 
                (wsel5.sb_entity_id IS NULL OR wsel5.sb_entity_id = sel.sb_market_id)
            STRAIGHT_JOIN gaming_promotions_wgr_sb_weights AS wght ON 
                wsel5.eligibility_criterias_id = wght.eligibility_criterias_id OR 
                promo.promotion_id = wght.promotion_id
            WHERE mul.odd >= wght.min_odd AND 
                (wght.sb_multiple_type_id IS NULL OR wght.sb_multiple_type_id = mul.sb_multiple_type_id) AND 
                (wght.sb_weight_range_id IS NULL OR SBWeightCheckRangeID(mul.sb_multiple_type_id, wght.sb_weight_range_id) IS NOT NULL) AND                   
                (wght.max_odd IS NULL OR mul.odd < wght.max_odd)
            GROUP BY crit.promotion_id, ggr.game_round_id 
        ) AS sb_weights_multiple ON 
            gaming_game_rounds.game_round_id = sb_weights_multiple.game_round_id AND 
            gaming_promotions.promotion_id = sb_weights_multiple.promotion_id AND 
            pps.promotion_id = sb_weights_multiple.promotion_id AND
            (gaming_promotions.min_odd IS NULL OR sb_weights_multiple.odd >= gaming_promotions.min_odd)
        LEFT JOIN gaming_promotions_achievement_amounts ON
            gaming_promotions.promotion_id = gaming_promotions_achievement_amounts.promotion_id AND
            pps.currency_id = gaming_promotions_achievement_amounts.currency_id AND
            ( gaming_promotions.is_single = 0 OR 
              CASE
                WHEN gaming_promotions.promotion_achievement_type_id=1 THEN IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, bet_real, bet_total)
                WHEN gaming_promotions.promotion_achievement_type_id=2 THEN IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, win_real-bet_real, win_total-bet_total)
                ELSE NULL
              END * IF(sb_weights.weight IS NULL OR sb_weights_multiple.weight IS NULL, 
                        COALESCE(sb_weights.weight, sb_weights_multiple.weight), 
                        LEAST(sb_weights.weight, sb_weights_multiple.weight)
                      ) >= gaming_promotions_achievement_amounts.amount
            )
        LEFT JOIN gaming_promotions_achievement_rounds ON
            gaming_promotions.promotion_id = gaming_promotions_achievement_rounds.promotion_id AND
            pps.currency_id = gaming_promotions_achievement_rounds.currency_id
        LEFT JOIN gaming_promotions_status_days ON
            gaming_promotions.promotion_id = gaming_promotions_status_days.promotion_id AND
            DATE(gaming_game_rounds.date_time_start) = gaming_promotions_status_days.day_start_time
        LEFT JOIN gaming_promotions_player_statuses_daily AS ppsd ON
            pps.promotion_player_status_id = ppsd.promotion_player_status_id AND
            gaming_promotions_status_days.promotion_status_day_id = ppsd.promotion_status_day_id
        LEFT JOIN gaming_promotion_wager_restrictions AS wager_restrictions ON
            wager_restrictions.promotion_id = gaming_promotions.promotion_id AND
            wager_restrictions.currency_id = pps.currency_id
        LEFT JOIN gaming_promotions_prize_amounts AS gppa ON
            gaming_promotions.promotion_id = gppa.promotion_id AND 
            pps.currency_id = gppa.currency_id 
        WHERE
            (   singlePromotionsEnabled OR gaming_promotions.is_single=0 ) AND
            (   pps.promotion_recurrence_date_id IS NULL OR
                gaming_promotions_status_days.promotion_recurrence_date_id IS NULL OR 
                pps.promotion_recurrence_date_id = gaming_promotions_status_days.promotion_recurrence_date_id ) AND        
            (   (   gaming_promotions_achievement_types.is_amount_achievement AND 
                    gaming_promotions_achievement_amounts.promotion_id IS NOT NULL ) OR 
                (   gaming_promotions_achievement_types.is_round_achievement AND 
                    gaming_promotions_achievement_rounds.promotion_id IS NOT NULL AND 
                    IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, gaming_game_rounds.bet_real, gaming_game_rounds.bet_total)>=gaming_promotions_achievement_rounds.min_bet_amount )
            ) AND 
            ( IFNULL(ppsd.daily_requirement_achieved, 0) = 0 OR gaming_game_plays.payment_transaction_type_id = 20 ) AND
            ( sb_weights.weight IS NOT NULL OR sb_weights_multiple.weight IS NOT NULL )
        ORDER BY gaming_game_rounds.game_round_id, IF(onBetTakesPrecedenced AND gaming_promotions_achievement_types.name = 'Bet', pps.priority - 1000, pps.priority) ASC, pps.opted_in_date DESC 
      ) AS PP
    ) AS PP
    WHERE PP.promotion_type='BET' AND round_row_count <= @max_contributions_per_round 
    GROUP BY game_round_id, promotion_player_status_id
    ON DUPLICATE KEY UPDATE 
        promotion_player_status_day_id = VALUES(promotion_player_status_day_id), 
        promotion_wgr_req_weight = VALUES(promotion_wgr_req_weight), 
        bet = VALUES(bet) - bet, 
        win = VALUES(win) - win, 
        loss = VALUES(loss) - loss, 
        game_play_process_counter_id = VALUES(game_play_process_counter_id);    
  END IF;
  
  
  UPDATE gaming_promotions_player_statuses_daily AS ppsd
  JOIN
  (
    SELECT ppsd.promotion_player_status_day_id, gaming_promotions_achievement_types.name AS ach_type, 
      gaming_promotions_achievement_amounts.amount AS ach_amount, gaming_promotions_achievement_rounds.num_rounds AS ach_num_rounds,
      SUM(promotion_contributions.bet) AS bet_total, SUM(promotion_contributions.win) AS win_total, SUM(promotion_contributions.loss) AS loss_total, 
      SUM(IF(promotion_contributions.bet > 0, 1, -1)) AS rounds
    FROM gaming_game_rounds_promotion_contributions AS promotion_contributions 
    JOIN gaming_promotions_player_statuses AS pps ON 
      promotion_contributions.game_play_process_counter_id=@gamePlayProcessCounterID AND
      promotion_contributions.promotion_player_status_id=pps.promotion_player_status_id
    JOIN gaming_promotions_player_statuses_daily AS ppsd ON 
      promotion_contributions.promotion_player_status_day_id=ppsd.promotion_player_status_day_id
    JOIN gaming_promotions ON pps.promotion_id=gaming_promotions.promotion_id
    JOIN gaming_promotions_achievement_types ON 
      gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
    LEFT JOIN gaming_promotions_achievement_amounts ON
      gaming_promotions.promotion_id=gaming_promotions_achievement_amounts.promotion_id AND
      pps.currency_id=gaming_promotions_achievement_amounts.currency_id
    LEFT JOIN gaming_promotions_achievement_rounds ON
      gaming_promotions.promotion_id=gaming_promotions_achievement_rounds.promotion_id AND
      pps.currency_id=gaming_promotions_achievement_rounds.currency_id
    GROUP BY ppsd.promotion_player_status_day_id  
  ) AS Totals ON ppsd.promotion_player_status_day_id=Totals.promotion_player_status_day_id
  SET 
    ppsd.day_bet=ppsd.day_bet+Totals.bet_total,
    ppsd.day_win=ppsd.day_win+Totals.win_total,
    ppsd.day_loss=ppsd.day_loss+Totals.loss_total,
    ppsd.day_num_rounds=ppsd.day_num_rounds+Totals.rounds,
    ppsd.daily_requirement_achieved_temp=ppsd.daily_requirement_achieved,
    ppsd.daily_requirement_achieved=IF(ppsd.daily_requirement_achieved=1 AND Totals.bet_total > 0, 1,
      CASE 
        WHEN ach_type='BET' THEN (ppsd.day_bet+Totals.bet_total) >= ach_amount
        WHEN ach_type='WIN' THEN (ppsd.day_win+Totals.win_total) >= ach_amount
        WHEN ach_type='LOSS' THEN (ppsd.day_loss+Totals.loss_total) >= ach_amount
        WHEN ach_type='ROUNDS' THEN (ppsd.day_num_rounds+Totals.rounds) >= ach_num_rounds
        ELSE 0
      END),
    ppsd.achieved_amount=GREATEST(0, ROUND(
      CASE 
        WHEN ach_type='BET' THEN LEAST(ppsd.day_bet+Totals.bet_total, ach_amount)
        WHEN ach_type='WIN' THEN LEAST(ppsd.day_win+Totals.win_total, ach_amount)
        WHEN ach_type='LOSS' THEN LEAST(ppsd.day_loss+Totals.loss_total, ach_amount)
        WHEN ach_type='ROUNDS' THEN LEAST(ppsd.day_num_rounds+Totals.rounds, ach_num_rounds)
        ELSE 0
      END, 0)),  
    ppsd.achieved_percentage=GREATEST(0, IFNULL(LEAST(1, ROUND(IF(ppsd.daily_requirement_achieved=1 AND Totals.bet_total > 0, 1,
      CASE 
        WHEN ach_type='BET' THEN (ppsd.day_bet+Totals.bet_total) / ach_amount 
        WHEN ach_type='WIN' THEN (ppsd.day_win+Totals.win_total) / ach_amount 
        WHEN ach_type='LOSS' THEN (ppsd.day_loss+Totals.loss_total) / ach_amount
        WHEN ach_type='ROUNDS' THEN (ppsd.day_num_rounds+Totals.rounds) / ach_num_rounds 
        ELSE 0
      END), 4)), 0));  
      
  
  UPDATE 
  (
    SELECT ppsd.promotion_player_status_day_id, SUM(IF(promotion_contributions.bet > 0, 1, -1)) AS rounds
    FROM gaming_game_rounds_promotion_contributions AS promotion_contributions 
    JOIN gaming_promotions_player_statuses AS pps ON 
      promotion_contributions.game_play_process_counter_id=@gamePlayProcessCounterID AND
      promotion_contributions.promotion_player_status_id=pps.promotion_player_status_id
    JOIN gaming_promotions_player_statuses_daily AS ppsd ON promotion_contributions.promotion_player_status_day_id=ppsd.promotion_player_status_day_id
    JOIN gaming_promotions ON pps.promotion_id=gaming_promotions.promotion_id
    GROUP BY ppsd.promotion_player_status_day_id  
  ) AS Totals 
  STRAIGHT_JOIN gaming_promotions_player_statuses_daily AS ppsd ON ppsd.promotion_player_status_day_id=Totals.promotion_player_status_day_id
  STRAIGHT_JOIN gaming_promotions_status_days AS psd ON ppsd.promotion_status_day_id=psd.promotion_status_day_id 
  STRAIGHT_JOIN gaming_promotions_player_statuses_daily AS c_ppsd ON c_ppsd.promotion_player_status_id=ppsd.promotion_player_status_id
  STRAIGHT_JOIN gaming_promotions_status_days AS c_psd ON 
    c_ppsd.promotion_status_day_id=c_psd.promotion_status_day_id AND
    ((psd.day_no=1 AND c_psd.day_no=1) OR (psd.day_no>1 AND c_psd.day_no=psd.day_no-1))
  SET
    ppsd.conseq_cur=c_ppsd.conseq_cur+Totals.rounds
  WHERE
    (ppsd.daily_requirement_achieved=1 AND ppsd.daily_requirement_achieved_temp=0) OR Totals.rounds < 0; 
  
  SET @numDaysAchieved=0;  
    
  
  UPDATE 
  (
    SELECT pps.promotion_player_status_id, gaming_promotions_achievement_types.name AS ach_type, 
      achievement_daily_flag, achievement_daily_consequetive_flag, achievement_days_num,
      gaming_promotions_achievement_amounts.amount AS ach_amount, gaming_promotions_achievement_rounds.num_rounds AS ach_num_rounds,
      SUM(promotion_contributions.bet) AS bet_total, SUM(promotion_contributions.win) AS win_total, SUM(promotion_contributions.loss) AS loss_total, 
      SUM(IF(promotion_contributions.bet > 0, 1, -1)) AS rounds
    FROM gaming_game_rounds_promotion_contributions AS promotion_contributions 
    STRAIGHT_JOIN gaming_promotions_player_statuses AS pps ON 
      promotion_contributions.game_play_process_counter_id=@gamePlayProcessCounterID AND
      promotion_contributions.promotion_player_status_id=pps.promotion_player_status_id
    STRAIGHT_JOIN gaming_promotions ON pps.promotion_id=gaming_promotions.promotion_id
    STRAIGHT_JOIN gaming_promotions_achievement_types ON gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
    LEFT JOIN gaming_promotions_achievement_amounts ON
      gaming_promotions.promotion_id=gaming_promotions_achievement_amounts.promotion_id AND
      pps.currency_id=gaming_promotions_achievement_amounts.currency_id
    LEFT JOIN gaming_promotions_achievement_rounds ON
      gaming_promotions.promotion_id=gaming_promotions_achievement_rounds.promotion_id AND
      pps.currency_id=gaming_promotions_achievement_rounds.currency_id
    GROUP BY pps.promotion_player_status_id  
  ) AS Totals 
  STRAIGHT_JOIN gaming_promotions_player_statuses AS pps ON pps.promotion_player_status_id=Totals.promotion_player_status_id
  STRAIGHT_JOIN gaming_promotions ON pps.promotion_id=gaming_promotions.promotion_id
  LEFT JOIN gaming_promotions_prize_amounts AS prize_amount ON pps.promotion_id = prize_amount.promotion_id AND pps.currency_id=prize_amount.currency_id
  SET 
    gaming_promotions.player_statuses_used=1,
    pps.total_bet=pps.total_bet+Totals.bet_total, 
    pps.total_win=pps.total_win+Totals.win_total,
    pps.total_loss=pps.total_loss+Totals.loss_total,
    pps.num_rounds=pps.num_rounds+Totals.rounds,
	pps.single_achieved_num=LEAST(IF(gaming_promotions.is_single, single_achieved_num+Totals.rounds, pps.single_achieved_num), gaming_promotions.single_repeat_for),
    pps.requirement_achieved=IF(pps.requirement_achieved=1, 1, IF (gaming_promotions.achieved_disabled, 0,
      CASE
		WHEN gaming_promotions.is_single THEN
		 (gaming_promotions.single_repeat_for=LEAST(pps.single_achieved_num+Totals.rounds, gaming_promotions.single_repeat_for))
        WHEN gaming_promotions.achievement_daily_flag=0 THEN
          CASE 
            WHEN ach_type='BET' THEN (pps.total_bet+Totals.bet_total) >= ach_amount
            WHEN ach_type='WIN' THEN (pps.total_win+Totals.win_total) >= ach_amount
            WHEN ach_type='LOSS' THEN (pps.total_loss+Totals.loss_total) >= ach_amount
            WHEN ach_type='ROUNDS' THEN (pps.num_rounds+Totals.rounds) >= ach_num_rounds
            ELSE 0
          END  
        WHEN gaming_promotions.achievement_daily_flag=1 AND gaming_promotions.achievement_daily_consequetive_flag=0 THEN
          (
            SELECT @numDaysAchieved:=LEAST(COUNT(1), gaming_promotions.achievement_days_num) AS achievement_days_cur
            FROM gaming_promotions_player_statuses_daily
            WHERE pps.promotion_player_status_id=gaming_promotions_player_statuses_daily.promotion_player_status_id 
				AND gaming_promotions_player_statuses_daily.daily_requirement_achieved=1
          ) >= gaming_promotions.achievement_days_num
        WHEN gaming_promotions.achievement_daily_flag=1 AND gaming_promotions.achievement_daily_consequetive_flag=1 THEN 
          (
            SELECT @numDaysAchieved:=LEAST(MAX(conseq_cur), gaming_promotions.achievement_days_num)
            FROM gaming_promotions_player_statuses_daily
            WHERE pps.promotion_player_status_id=gaming_promotions_player_statuses_daily.promotion_player_status_id
            
          ) >= gaming_promotions.achievement_days_num
      END)),
    pps.achieved_amount=GREATEST(0, ROUND(
      IF (gaming_promotions.achievement_daily_flag=0,
        CASE 
		  WHEN ach_type='BET' AND gaming_promotions.is_single THEN pps.total_bet+LEAST(Totals.bet_total, prize_amount.max_cap*Totals.rounds)
          WHEN ach_type='WIN' AND gaming_promotions.is_single THEN pps.total_win+LEAST(Totals.win_total, prize_amount.max_cap*Totals.rounds)
		  WHEN ach_type='BET' THEN LEAST(pps.total_bet+Totals.bet_total, ach_amount)
          WHEN ach_type='WIN' THEN LEAST(pps.total_win+Totals.win_total, ach_amount)
          WHEN ach_type='LOSS' THEN LEAST(pps.total_loss+Totals.loss_total, ach_amount)
          WHEN ach_type='ROUNDS' THEN LEAST(pps.num_rounds+Totals.rounds, ach_num_rounds)
          ELSE 0
        END,
        CASE 
          WHEN ach_type='BET' THEN LEAST(ach_amount*@numDaysAchieved, ach_amount*gaming_promotions.achievement_days_num)
          WHEN ach_type='WIN' THEN LEAST(ach_amount*@numDaysAchieved, ach_amount*gaming_promotions.achievement_days_num)
          WHEN ach_type='LOSS' THEN LEAST(ach_amount*@numDaysAchieved, ach_amount*gaming_promotions.achievement_days_num)
          WHEN ach_type='ROUNDS' THEN LEAST(ach_num_rounds*@numDaysAchieved, ach_num_rounds*gaming_promotions.achievement_days_num)
          ELSE 0
        END
      ), 0)),  
    pps.achieved_percentage=GREATEST(0, IFNULL(LEAST(1, ROUND(IF(pps.requirement_achieved=1,1,
      CASE
        WHEN gaming_promotions.achievement_daily_flag=0 THEN
          CASE 
			WHEN gaming_promotions.is_single THEN LEAST(pps.single_achieved_num+Totals.rounds, gaming_promotions.single_repeat_for)/gaming_promotions.single_repeat_for
            WHEN ach_type='BET' THEN (pps.total_bet+Totals.bet_total) / ach_amount 
            WHEN ach_type='WIN' THEN (pps.total_win+Totals.win_total) / ach_amount 
            WHEN ach_type='LOSS' THEN (pps.total_loss+Totals.loss_total) / ach_amount
            WHEN ach_type='ROUNDS' THEN (pps.num_rounds+Totals.rounds) / ach_num_rounds 
            ELSE 0
          END  
        WHEN gaming_promotions.achievement_daily_flag=1 THEN 
          @numDaysAchieved/gaming_promotions.achievement_days_num
      END),4)), 0)),
    pps.achieved_days=IF(gaming_promotions.achievement_daily_flag=1, IF(pps.requirement_achieved=1, gaming_promotions.achievement_days_num, @numDaysAchieved), NULL)
	WHERE pps.is_current AND pps.is_active;
  
    
	UPDATE gaming_game_rounds_promotion_contributions AS promotion_contributions
	STRAIGHT_JOIN gaming_promotions_player_statuses AS pps ON 
	  promotion_contributions.game_play_process_counter_id=@gamePlayProcessCounterID AND
	  pps.promotion_player_status_id=promotion_contributions.promotion_player_status_id AND
	  pps.requirement_achieved=1 AND requirement_achieved_date IS NULL
	SET pps.requirement_achieved_date=NOW();

  SELECT value_bool INTO promotionAwardPrizeOnAchievementEnabled FROM gaming_settings WHERE name='PROMOTION_AWARD_PRIZE_ON_ACHIEVEMENT_ENABLED';
  IF (promotionAwardPrizeOnAchievementEnabled=1) THEN
    
    OPEN promotionAwardOnAchievementCursor;
    allPromotionsOnAchievement: LOOP 
      SET noMoreRecords=0;
      FETCH promotionAwardOnAchievementCursor INTO promotionID, promotionRecurrenceID;
      IF (noMoreRecords) THEN
        LEAVE allPromotionsOnAchievement;
      END IF;
    
      CALL PromotionAwardPrizeOnAchievement(promotionID, promotionRecurrenceID);
    
    END LOOP allPromotionsOnAchievement;
    CLOSE promotionAwardOnAchievementCursor;
  END IF;

  IF (singlePromotionsEnabled=1) THEN
    
    OPEN promotionAwardSingleCursor;
    allPromotionsOnSingle: LOOP 
      SET noMoreRecords=0;
      FETCH promotionAwardSingleCursor INTO promotionID, promotionRecurrenceID;
      IF (noMoreRecords) THEN
        LEAVE allPromotionsOnSingle;
      END IF;
   
	 CALL PromotionAwardPrizeForSingle(promotionID, promotionRecurrenceID);
    
    END LOOP allPromotionsOnSingle;
    CLOSE promotionAwardSingleCursor;
  END IF; 


END root$$

DELIMITER ;

