DROP procedure IF EXISTS `PlayReturnBonusInfoOnWinForSbExtraID`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayReturnBonusInfoOnWinForSbExtraID`(sbExtraID BIGINT, licenseTypeID TINYINT(4))
BEGIN
  -- Initial Version

   SELECT ggpbiw.win_game_play_id, ggpbiw.bonus_rule_id, gaming_bonus_rules.name AS bonus_rule_name, ggpbiw.bonus_instance_id,
   0 AS wager_contribution,IF(bonus_order = 1,gaming_game_plays.amount_real,0) AS amount_real, win_bonus AS amount_bonus, win_bonus_win_locked AS amount_bonus_win_locked, 
    IF(is_secured =1 OR (is_free_bonus=1 AND bonus_order = 1),LEAST(win_bonus-lost_win_bonus, ggpbiw.win_real),0) AS transfered_bonus,
	IF(is_secured =1 OR (is_free_bonus=1 AND bonus_order = 1),GREATEST(0,ggpbiw.win_real - LEAST(win_bonus-lost_win_bonus,ggpbiw.win_real)),0) AS transfered_bonus_win_locked, gaming_bonus_instances.is_secured AS bonus_requirement_met, 0 AS partial_bonus_released,
   0 AS ring_fenced_transfered, gaming_game_plays.pending_winning_real, IFNULL(gaming_transactions.amount_total,0) as amount_total, gaming_game_plays.amount_cash
  FROM gaming_game_plays 
  JOIN gaming_payment_transaction_type ON gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND gaming_payment_transaction_type.name='Win'
  JOIN gaming_game_plays_bonus_instances_wins AS ggpbiw ON ggpbiw.win_game_play_id=gaming_game_plays.game_play_id
  JOIN gaming_bonus_rules ON ggpbiw.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
  JOIN gaming_bonus_instances ON ggpbiw.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
  LEFT JOIN gaming_transactions ON gaming_transactions.payment_transaction_type_id = 138 AND gaming_transactions.extra_id = gaming_game_plays.game_play_id_win
  WHERE gaming_game_plays.sb_extra_id=sbExtraID AND gaming_game_plays.license_type_id=licenseTypeID;

END$$

DELIMITER ;

