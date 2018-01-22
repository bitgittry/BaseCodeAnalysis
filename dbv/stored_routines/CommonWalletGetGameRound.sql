DROP procedure IF EXISTS `CommonWalletGetGameRound`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletGetGameRound`(gameManufacturerName VARCHAR(80), roundRef VARCHAR(80))
BEGIN 
 
  SET @game_manufacturer=gameManufacturerName;
  SET @round_ref=roundRef;
  SELECT game_round_id, bet_total, bet_total_base, bet_real, bet_cash, bet_bonus, bet_bonus_win_locked, jackpot_contribution, win_total, win_total_base, win_real, win_cash, win_bonus, win_bonus_win_locked, bonus_lost, bonus_win_locked_lost, 
    date_time_start, date_time_end, is_round_finished, game_id, gaming_game_rounds.game_manufacturer_id, operator_game_id, client_stat_id, balance_real_after, balance_bonus_after, num_bets, 
    gaming_game_round_types.name AS round_type, round_ref, amount_tax_operator, amount_tax_player, amount_tax_operator_bonus, amount_tax_player_bonus, balance_real_before, balance_bonus_before, loyalty_points, loyalty_points_bonus
  FROM gaming_game_rounds 
  JOIN gaming_game_manufacturers ON gaming_game_rounds.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id
  WHERE  gaming_game_manufacturers.name=@game_manufacturer AND gaming_game_rounds.round_ref=@round_ref; 
  
END$$
DELIMITER ;