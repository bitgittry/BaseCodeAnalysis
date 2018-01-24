DROP procedure IF EXISTS `CommonWalletColossusInitializeRequest`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletColossusInitializeRequest`(poolID BIGINT, sessionKey VARCHAR(80), betAmount DECIMAL(18, 5), stakeAmount DECIMAL(18, 5), realMoneyOnly TINYINT(1), ignoreSessionExpiry TINYINT(1), OUT statusCode INT)
root:BEGIN

	DECLARE balanceReal, balanceBonus, balanceWinLocked, balanceFreeBet,balanceFreeBetWinLocked,fraudClientEventID,bonusMismatch,betRemain,loyaltyBetBonus,
	betReal, betBonus, betBonusWinLocked,totalPlayerBalance,minStake,maxStake,minCost,maxCost,poolExchangeRate DECIMAL(18, 5) DEFAULT 0;
	DECLARE clientStatID, clientID,sessionID,gamePlayBetCounterID,poolIDCheck,cwTransactionID,gameManufacturerID,currencyID BIGINT DEFAULT -1;
	DECLARE playLimitEnabled, bonusEnabledFlag, fraudEnabled, playerRestrictionEnabled,isAccountClosed, isPlayAllowed, disallowPlay,isLimitExceeded,ignorePlayLimit, licenceCountryRestriction TINYINT(1) DEFAULT 0;
	DECLARE sessionStatusCode,numBonuses, fixtureCount,numApplicableBonuses INT DEFAULT 0;
	DECLARE extPoolID,extPoolTypeID,licenseType VARCHAR(80);
	DECLARE licenseTypeID TINYINT(4);
	DECLARE endDate DATETIME;

    SET gameManufacturerID = 18;
	SET licenseType = 'poolbetting';
	SET ignorePlayLimit=0;


	SELECT client_stat_id, gaming_client_stats.client_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, IF(gaming_clients.is_account_closed OR gaming_fraud_rule_client_settings.block_account,1,0), gaming_clients.is_play_allowed AND !gaming_fraud_rule_client_settings.block_gameplay, sessions_main.session_id, sessions_main.status_code, gaming_client_stats.currency_id
	INTO clientStatID, clientID, balanceReal, balanceBonus, balanceWinLocked,isAccountClosed, isPlayAllowed, sessionID, sessionStatusCode,currencyID
	FROM gaming_client_stats
	JOIN gaming_clients ON gaming_clients.client_id = gaming_client_stats.client_id
    LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id
	JOIN sessions_main ON session_guid = sessionKey AND extra2_id = gaming_client_stats.client_stat_id
	WHERE gaming_client_stats.is_active=1 
	FOR UPDATE;

	SELECT gaming_pb_pools.pb_pool_id,ext_pool_id, COUNT(*) AS fixture_count,ext_pool_type_id, min_stake,max_stake, min_cost,max_cost,gaming_pb_competitions.end_date_utc,exchange_rate
	INTO poolIDCheck,extPoolID,fixtureCount,extPoolTypeID,minStake,maxStake,minCost,maxCost,endDate,poolExchangeRate
	FROM gaming_pb_pools
	JOIN gaming_pb_pool_fixtures ON gaming_pb_pool_fixtures.pb_pool_id = gaming_pb_pools.pb_pool_id
	JOIN gaming_pb_fixtures ON gaming_pb_pool_fixtures.pb_fixture_id = gaming_pb_fixtures.pb_fixture_id
	JOIN gaming_pb_pool_types ON gaming_pb_pool_types.pb_pool_type_id = gaming_pb_pools.pb_pool_type_id
	JOIN gaming_pb_competition_pools ON gaming_pb_competition_pools.pb_pool_id = gaming_pb_pools.pb_pool_id
	JOIN gaming_pb_competitions ON gaming_pb_competitions.pb_competition_id = gaming_pb_competition_pools.pb_competition_id
	JOIN gaming_pb_pool_exchange_rates ON gaming_pb_pool_exchange_rates.pb_pool_id = gaming_pb_pools.pb_pool_id AND gaming_pb_pool_exchange_rates.currency_id = currencyID
	WHERE gaming_pb_pools.pb_pool_id = poolID AND is_cancelled = 0 GROUP BY gaming_pb_pools.pb_pool_id;

	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, gs4.value_bool, IFNULL(gs5.value_bool,0) AS vb5
	INTO playLimitEnabled, bonusEnabledFlag, fraudEnabled, playerRestrictionEnabled, licenceCountryRestriction
	FROM gaming_settings gs1 
	JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
	JOIN gaming_settings gs3 ON (gs3.name='FRAUD_ENABLED')
	JOIN gaming_settings gs4 ON (gs4.name='PLAYER_RESTRICTION_ENABLED')
	LEFT JOIN gaming_settings gs5 ON (gs5.name='LICENCE_COUNTRY_RESTRICTION_ENABLED')
	WHERE gs1.name='PLAY_LIMIT_ENABLED';

	IF(licenceCountryRestriction) THEN
	  SELECT license_type_id INTO licenseTypeID FROM gaming_license_type WHERE name = licenseType;
	  -- Check if there are any country/ip restrictions for this player 
	  IF (SELECT !WagerRestrictionCheckCanWager(licenseTypeID, sessionID)) THEN 
		SET statusCode=15; 
		LEAVE root;
	  END IF;
    END IF;

	IF (clientStatID=-1 OR isAccountClosed=1) THEN
		SET statusCode=1;
	ELSEIF (isPlayAllowed=0) THEN 
		SET statusCode=2; 
	ELSEIF (betAmount > (balanceReal+balanceBonus+balanceWinLocked)) THEN
		SET statusCode=3;
	ELSEIF (ignoreSessionExpiry=0 AND sessionStatusCode!=1) THEN
		SET statusCode=4;
	ELSEIF (poolIDCheck = -1) THEN
		SET statusCode = 10;
	ELSEIF (minCost IS NOT NULL AND  betAmount/poolExchangeRate < minCost) THEN
		SET statusCode = 11;
	ELSEIF (maxCost IS NOT NULL AND  betAmount/poolExchangeRate > maxCost) THEN
		SET statusCode = 11;
	ELSEIF (minStake IS NOT NULL AND  stakeAmount/poolExchangeRate < minStake) THEN
		SET statusCode = 12;
	ELSEIF (maxStake IS NOT NULL AND  stakeAmount/poolExchangeRate > maxStake) THEN
		SET statusCode = 12;
	END IF;

	IF (statusCode > 0) THEN
		LEAVE root;
	END IF;
	
    
	SET numApplicableBonuses =0;
	

	
	IF (bonusEnabledFlag=0 OR realMoneyOnly=1) THEN
		SET balanceBonus=0;
		SET balanceWinLocked=0; 
		SET balanceFreeBet=0; 
		SET balanceFreeBetWinLocked=0;
	END IF;

	
	IF (playerRestrictionEnabled) THEN
		SET @numRestrictions=0;
		SET @restrictionType=NULL;
		SELECT restriction_types.name, COUNT(*) INTO @restrictionType, @numRestrictions
		FROM gaming_player_restrictions
		JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_play=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
		LEFT JOIN gaming_license_type ON gaming_player_restrictions.license_type_id=gaming_license_type.license_type_id
		WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date AND
		  (gaming_license_type.name IS NULL OR gaming_license_type.name=licenseType);

		IF (@numRestrictions > 0) THEN
			SET statusCode=5;
			LEAVE root;
		END IF;
	END IF;  

	
	IF (fraudEnabled AND ignorePlayLimit=0) THEN
		SELECT fraud_client_event_id, disallow_play 
		INTO fraudClientEventID, disallowPlay
		FROM gaming_fraud_client_events 
		JOIN gaming_fraud_classification_types ON gaming_fraud_client_events.client_stat_id=clientStatID AND gaming_fraud_client_events.is_current=1
		  AND gaming_fraud_client_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id;

		IF (fraudClientEventID<>-1 AND disallowPlay=1) THEN
			SET statusCode=6;
			LEAVE root;
		END IF;
	END IF;

	SET totalPlayerBalance = IF(realMoneyOnly=1, balanceReal, balanceReal+(balanceBonus+balanceWinLocked)+(balanceFreeBet+balanceFreeBetWinLocked));

	
	IF (totalPlayerBalance < betAmount) THEN 
		SET statusCode=7;
		LEAVE root;
	END IF;

	
	IF (playLimitEnabled AND ignorePlayLimit=0) THEN 
		SET isLimitExceeded=PlayLimitCheckExceeded(betAmount, sessionID, clientStatID, licenseType);
		IF (isLimitExceeded>0) THEN
			SET statusCode=8;
			LEAVE root;
		END IF;
	END IF;

	
	IF (bonusEnabledFlag AND realMoneyOnly=0) THEN
		SELECT IF(current_bonus_balance!=IFNULL(bonus_amount_remaining,0) OR current_bonus_win_locked_balance!=IFNULL(current_win_locked_amount,0), 1, 0) 
		INTO bonusMismatch 
		FROM gaming_client_stats 
		LEFT JOIN
		(
			SELECT client_stat_id, SUM(bonus_amount_remaining) AS bonus_amount_remaining, SUM(current_win_locked_amount) AS current_win_locked_amount
			FROM gaming_bonus_instances
			WHERE client_stat_id=clientStatID AND is_active=1
			GROUP BY client_stat_id
		) AS PB ON gaming_client_stats.client_stat_id=PB.client_stat_id
		WHERE gaming_client_stats.client_stat_id=clientStatID; 

		IF (bonusMismatch=1) THEN
			CALL BonusAdjustBonusBalance(clientStatID);
		END IF;
	END IF;

	SET betRemain=betAmount;

	IF (realMoneyOnly=0 AND bonusEnabledFlag AND (numApplicableBonuses>0)) THEN 
	  
		SET @betRemain=betRemain;
		SET @bonusCounter=0;
		SET @betReal=0;
		SET @betBonus=0;
		SET @betBonusWinLocked=0;
		SET @freeBetBonus=0;

		INSERT INTO gaming_game_plays_bet_counter (date_created, client_stat_id) VALUES (NOW(), clientStatID);
		SET gamePlayBetCounterID=LAST_INSERT_ID();

		INSERT INTO gaming_game_plays_bonus_instances_pre (game_play_bet_counter_id, bonus_instance_id, bet_total, bet_real, bet_bonus, bet_bonus_win_locked, bonus_order, no_loyalty_points)
		SELECT gamePlayBetCounterID, bonus_instance_id, bet_real+free_bet_bonus+bet_bonus+bet_bonus_win_locked AS bet_total, bet_real, bet_bonus+free_bet_bonus, bet_bonus_win_locked, bonusCounter, no_loyalty_points
		FROM
		(
			SELECT
			bonus_instance_id AS bonus_instance_id, 
			@freeBetBonus:=IF(realMoneyOnly, 0, IF(awarding_type='FreeBet', IF(bonus_amount_remaining>@betRemain, @betRemain, bonus_amount_remaining), 0)) AS free_bet_bonus,
			@betRemain:=@betRemain-@freeBetBonus,   
			@betReal:=IF(@bonusCounter=0, IF(balanceReal>@betRemain, @betRemain, balanceReal), 0) AS bet_real,
			@betRemain:=@betRemain-@betReal,  
			@betBonusWinLocked:=IF(realMoneyOnly, 0, IF(current_win_locked_amount>@betRemain, @betRemain, current_win_locked_amount)) AS bet_bonus_win_locked,
			@betRemain:=@betRemain-@betBonusWinLocked,
			@betBonus:=IF(realMoneyOnly, 0, IF(awarding_type!='FreeBet',IF(bonus_amount_remaining>@betRemain, @betRemain, bonus_amount_remaining),0)) AS bet_bonus,
			@betRemain:=@betRemain-@betBonus, @bonusCounter:=@bonusCounter+1 AS bonusCounter, no_loyalty_points
			FROM
			(
			    SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_types_awarding.name AS awarding_type, bonus_amount_remaining, current_win_locked_amount, gaming_bonus_rules.no_loyalty_points
				FROM gaming_bonus_instances
				JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
				JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
				JOIN gaming_bonus_rules_wgr_req_weights ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules_wgr_req_weights.bonus_rule_id AND gaming_bonus_rules_wgr_req_weights.operator_game_id=operatorGameID 
				LEFT JOIN sessions_main ON sessions_main.session_id=sessionID
				LEFT JOIN gaming_bonus_rules_platform_types AS platform_types ON gaming_bonus_rules.bonus_rule_id=platform_types.bonus_rule_id AND sessions_main.platform_type_id=platform_types.platform_type_id
				WHERE (client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1) AND (gaming_bonus_rules.restrict_platform_type=0 OR platform_types.platform_type_id IS NOT NULL)
				ORDER BY gaming_bonus_types_awarding.`order` ASC, gaming_bonus_instances.priority ASC, gaming_bonus_instances.given_date ASC, gaming_bonus_instances.bonus_instance_id ASC
			) AS XX
		HAVING free_bet_bonus!=0 OR bet_real!=0 OR bet_bonus!=0 OR bet_bonus_win_locked!=0
		) AS XY;

		SELECT IFNULL(COUNT(*),0), SUM(bet_real), SUM(bet_bonus), SUM(bet_bonus_win_locked), SUM(IF(no_loyalty_points,0,bet_bonus+bet_bonus_win_locked))  
		INTO numBonuses, betReal, betBonus, betBonusWinLocked, loyaltyBetBonus 
		FROM gaming_game_plays_bonus_instances_pre
		WHERE game_play_bet_counter_id=gamePlayBetCounterID;

		IF (numBonuses IS NULL OR numBonuses=0) THEN
			SET betReal=LEAST(betRemain, balanceReal); SET betBonus=0; SET betBonusWinLocked=0; SET betRemain=betRemain-betReal; 
		ELSE
			SET betRemain=betRemain-(betReal+betBonus+betBonusWinLocked);
		END IF;
	ELSE 
		IF (betRemain > 0) THEN
			IF (balanceReal >= betRemain) THEN
				SET betReal=ROUND(betRemain, 5);
				SET betRemain=0;
			ELSE
				SET betReal=ROUND(balanceReal, 5);
				SET betRemain=ROUND(betRemain-betReal,0);
			END IF;
		END IF;
		SET betBonusWinLocked=0;
		SET betBonus=0;
	END IF;

	
	IF (betRemain > 0) THEN
		SET statusCode=9;
		LEAVE root;
	END IF;

    INSERT INTO gaming_cw_transactions (game_manufacturer_id, payment_transaction_type_id, cw_request_type_id, amount, transaction_ref, round_ref, game_ref, client_stat_id, game_play_id, timestamp, other_data, is_success, status_code)
    SELECT gaming_game_manufacturers.game_manufacturer_id, transaction_type.payment_transaction_type_id, request_type.cw_request_type_id, betAmount, UUID(), NULL, PoolID, clientStatID, NULL, NOW(), NULL, 0, 0
    FROM gaming_game_manufacturers
    JOIN gaming_payment_transaction_type AS transaction_type ON gaming_game_manufacturers.game_manufacturer_id=gameManufacturerID AND transaction_type.name='Bet'
    LEFT JOIN gaming_cw_request_types AS request_type ON request_type.name='PlaceBet' AND request_type.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id;
    SET cwTransactionID=LAST_INSERT_ID();

	INSERT INTO gaming_pb_bets (client_stat_id,timestamp,cw_transaction_id,stake_amount,cost_amount,num_lines,pb_pool_id)
	SELECT clientStatID, NOW(),LAST_INSERT_ID(),stakeAmount,betAmount,stakeAmount/unit_stake,pb_pool_id
	FROM gaming_pb_pools WHERE gaming_pb_pools.pb_pool_id = poolID;

	SELECT clientStatID AS client_stat_id, extPoolID AS ext_pool_id, betAmount AS bet_amount, betReal AS bet_real, betBonus AS bet_bonus,extPoolTypeID AS ext_pool_type_id,cwTransactionID AS cw_transaction_id,
	betBonusWinLocked AS bet_bonus_win_locked, gamePlayBetCounterID AS game_play_bet_counter_id, sessionID AS session_id, numBonuses AS num_bonuses,fixtureCount AS fixture_count, poolExchangeRate AS pool_exchange_rate;


	SET statusCode=0;
END root$$

DELIMITER ;

