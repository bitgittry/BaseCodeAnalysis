DROP procedure IF EXISTS `PlayReturnBonusInfoOnWin`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayReturnBonusInfoOnWin`(gamePlayID BIGINT)
BEGIN

  SELECT ggpbiw.bonus_rule_id, gaming_bonus_rules.name AS bonus_rule_name, ggpbiw.bonus_instance_id,
   0 AS wager_contribution, IF(bonus_order = 1,gaming_game_plays.amount_real,0) AS amount_real, win_bonus AS amount_bonus, win_bonus_win_locked AS amount_bonus_win_locked, 
    IF(is_secured =1 OR (is_free_bonus=1 AND bonus_order = 1),LEAST(win_bonus-lost_win_bonus, ggpbiw.win_real),0) + IFNULL(gaming_transactions.amount_total,0) AS transfered_bonus,
	IF(is_secured =1 OR (is_free_bonus=1 AND bonus_order = 1),GREATEST(0,ggpbiw.win_real - LEAST(win_bonus-lost_win_bonus,ggpbiw.win_real)),0) AS transfered_bonus_win_locked, gaming_bonus_instances.is_secured AS bonus_requirement_met, 0 AS partial_bonus_released,
   0 AS ring_fenced_transfered, IFNULL(gaming_transactions.amount_total,0) as amount_total, IF(bonus_order = 1,gaming_game_plays.amount_cash, 0) AS amount_cash
  FROM gaming_game_plays_bonus_instances_wins AS ggpbiw
  JOIN gaming_game_plays ON ggpbiw.win_game_play_id = gaming_game_plays.game_play_id
  JOIN gaming_bonus_rules ON ggpbiw.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
  JOIN gaming_bonus_instances ON ggpbiw.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
  LEFT JOIN gaming_transactions ON gaming_transactions.payment_transaction_type_id = 138 AND gaming_transactions.extra_id = gamePlayID
  WHERE ggpbiw.win_game_play_id=gamePlayID;

END$$

DELIMITER ;