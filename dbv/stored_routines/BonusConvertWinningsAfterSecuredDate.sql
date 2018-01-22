DROP procedure IF EXISTS `BonusConvertWinningsAfterSecuredDate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusConvertWinningsAfterSecuredDate`(gamePlayID BIGINT, gamePlayWinCounterID BIGINT)
BEGIN

	DECLARE clientStatID BIGINT;
	DECLARE betType VARCHAR(8);
	DECLARE bonusWinLockedTransferred,bonusTransferred, bonusTransferedLost,bonusWinLockedTransferedLost,exchangeRate DECIMAL(18,5);

	SELECT gs1.value_string
    INTO betType
    FROM gaming_settings gs1 
    WHERE gs1.name='PLAY_WAGER_TYPE';


	IF (betType = 'Type1') THEN

		SELECT 
		SUM(win_bonus_win_locked-lost_win_bonus_win_locked),
		SUM(win_bonus-lost_win_bonus),
		ggpbi.client_stat_id,ggpbi.exchange_rate,0,0
		-- SUM(lost_win_bonus),
	 -- 	SUM(lost_win_bonus_win_locked)
		INTO bonusWinLockedTransferred,bonusTransferred,clientStatID, exchangeRate, bonusTransferedLost,bonusWinLockedTransferedLost
		FROM gaming_game_plays_bonus_instances_wins AS ggpbi
		JOIN gaming_bonus_instances ON ggpbi.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
		JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
		JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id = ggpbi.bonus_instance_id 
		WHERE game_play_win_counter_id=gamePlayWinCounterID AND (gbi.is_secured OR is_free_bonus OR gaming_bonus_instances.is_freebet_phase);	

		UPDATE gaming_bonus_instances AS gbi
		JOIN gaming_game_plays_bonus_instances_wins AS ggpbi ON gbi.bonus_instance_id = ggpbi.bonus_instance_id 
		SET bonus_amount_remaining = 0, current_win_locked_amount=0
		WHERE game_play_win_counter_id=gamePlayWinCounterID AND is_secured;	

		UPDATE gaming_bonus_instances AS gbi
		JOIN gaming_game_plays_bonus_instances_wins AS ggpbi ON gbi.bonus_instance_id = ggpbi.bonus_instance_id 
		JOIN gaming_bonus_rules gbr ON gbr.bonus_rule_id = gbi.bonus_rule_id
		SET bonus_amount_remaining = bonus_amount_remaining-(win_bonus-lost_win_bonus), current_win_locked_amount=current_win_locked_amount-(win_bonus_win_locked-lost_win_bonus_win_locked),
		gbi.is_active = IF(open_rounds=0 AND bonus_amount_remaining-(win_bonus-lost_win_bonus) <=0 AND current_win_locked_amount-(win_bonus_win_locked-lost_win_bonus_win_locked)<=0,0,gbi.is_active),
		is_used_all = IF(open_rounds=0 AND bonus_amount_remaining-(win_bonus-lost_win_bonus) <=0 AND current_win_locked_amount-(win_bonus_win_locked-lost_win_bonus_win_locked)<=0,1,is_used_all),
		used_all_date = IF(open_rounds=0 AND bonus_amount_remaining-(win_bonus-lost_win_bonus) <=0 AND current_win_locked_amount-(win_bonus_win_locked-lost_win_bonus_win_locked)<=0 AND used_all_date IS NULL,NOW(),used_all_date)
		WHERE game_play_win_counter_id=gamePlayWinCounterID AND is_free_bonus;	

	ELSE

		SELECT 
		SUM(win_bonus_win_locked-lost_win_bonus_win_locked),
		IF(gaming_bonus_instances.is_freebet_phase OR gaming_bonus_rules.is_free_bonus,0,SUM(win_bonus-lost_win_bonus)),
		ggpbi.client_stat_id,ggpbi.exchange_rate,0,0
		-- SUM(lost_win_bonus),
	 -- 	SUM(lost_win_bonus_win_locked)
		INTO bonusWinLockedTransferred,bonusTransferred,clientStatID, exchangeRate, bonusTransferedLost,bonusWinLockedTransferedLost
		FROM gaming_game_plays_bonus_instances_wins AS ggpbi
		JOIN gaming_bonus_instances ON ggpbi.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
		JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
		JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id = ggpbi.bonus_instance_id 
		WHERE game_play_win_counter_id=gamePlayWinCounterID AND (gbi.is_secured OR is_free_bonus OR gaming_bonus_instances.is_freebet_phase);	

		UPDATE gaming_bonus_instances AS gbi
		JOIN gaming_game_plays_bonus_instances_wins AS ggpbi ON gbi.bonus_instance_id = ggpbi.bonus_instance_id 
		SET bonus_amount_remaining = 0, current_win_locked_amount=0
		WHERE game_play_win_counter_id=gamePlayWinCounterID AND is_secured;	

		UPDATE gaming_bonus_instances AS gbi
		JOIN gaming_game_plays_bonus_instances_wins AS ggpbi ON gbi.bonus_instance_id = ggpbi.bonus_instance_id 
		JOIN gaming_bonus_rules gbr ON gbr.bonus_rule_id = gbi.bonus_rule_id
		SET current_win_locked_amount=current_win_locked_amount-(win_bonus_win_locked-lost_win_bonus_win_locked),
		gbi.is_active = IF(open_rounds=0 AND bonus_amount_remaining <= 0 AND current_win_locked_amount-(win_bonus_win_locked-lost_win_bonus_win_locked)<=0,0,gbi.is_active),
		is_used_all = IF(open_rounds=0 AND bonus_amount_remaining <= 0 AND current_win_locked_amount-(win_bonus_win_locked-lost_win_bonus_win_locked)<=0,1,is_used_all),
		used_all_date = IF(open_rounds=0 AND bonus_amount_remaining <= 0 AND current_win_locked_amount-(win_bonus_win_locked-lost_win_bonus_win_locked)<=0 AND used_all_date IS NULL,NOW(),used_all_date)
		WHERE game_play_win_counter_id=gamePlayWinCounterID AND (gbi.is_freebet_phase OR is_free_bonus);

	END IF;

	CALL `PlaceBetBonusCashExchange`(clientStatID, gamePlayID, 0, 'BonusTurnedReal',exchangeRate ,
	bonusTransferred+bonusWinLockedTransferred, bonusTransferred, bonusWinLockedTransferred /*putting it all under bonus win locked*/ ,
	bonusTransferedLost, bonusWinLockedTransferedLost,
		NULL,0,0,0,0/* ring fencing */,NULL );
END$$

DELIMITER ;

