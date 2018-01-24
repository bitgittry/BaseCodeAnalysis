DROP procedure IF EXISTS `PlayReturnBonusInfoOnBet`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayReturnBonusInfoOnBet`(gamePlayID BIGINT)
BEGIN

  SELECT ggpbi.bonus_rule_id, gaming_bonus_rules.name AS bonus_rule_name, ggpbi.bonus_instance_id,
   ggpbi.wager_requirement_contribution - IFNULL(wager_requirement_contribution_cancelled, 0) AS wager_contribution, bet_real AS amount_real, bet_bonus AS amount_bonus, bet_bonus_win_locked AS amount_bonus_win_locked, 
   IFNULL(bonus_transfered,0) + IFNULL(gaming_transactions.amount_total,0) AS transfered_bonus, IFNULL(bonus_win_locked_transfered,0) AS transfered_bonus_win_locked, now_wager_requirement_met AS bonus_requirement_met, now_release_bonus AS partial_bonus_released,
   ring_fenced_transfered, IFNULL(gaming_transactions.amount_total,0) as amount_total, bet_cash AS amount_cash
  FROM gaming_game_plays_bonus_instances AS ggpbi
  JOIN gaming_bonus_rules ON ggpbi.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
  JOIN gaming_game_plays ON gaming_game_plays.game_play_id = gamePlayID
  LEFT JOIN gaming_transactions ON gaming_transactions.payment_transaction_type_id = 138 AND gaming_transactions.extra_id = gaming_game_plays.game_play_id_win
  WHERE ggpbi.game_play_id=gamePlayID;

END$$

DELIMITER ;

