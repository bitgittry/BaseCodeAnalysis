DROP PROCEDURE IF EXISTS CommonWalletGetGamePlay;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletGetGamePlay`(gameManufacturerName VARCHAR(80), transactionRef VARCHAR(80))
root:BEGIN 
  SET @game_manufacturer=gameManufacturerName;
  SET @transaction_ref=transactionRef;
  
  SELECT  gaming_game_plays.game_play_id, 
          gaming_game_plays.game_round_id, 
          gaming_payment_transaction_type.name AS transaction_type, 
          amount_total, 
          amount_total_base, 
          amount_real, 
          amount_cash,
          amount_ring_fenced,
          amount_bonus,           
          amount_bonus_win_locked, 
          amount_other,
          jackpot_contribution, 
          bonus_lost, 
          bonus_win_locked_lost, 
          gaming_game_plays.timestamp, 
          gaming_game_plays.exchange_rate, 
          game_id, 
          gaming_game_plays.game_manufacturer_id, 
          operator_game_id, 
          gaming_game_plays.client_stat_id, 
          game_session_id, 
          balance_real_after, 
          balance_bonus_after, 
          is_win_placed, 
          is_processed, 
          game_play_id_win, 
	      amount_tax_operator, 
          amount_tax_player, 
          loyalty_points, 
          loyalty_points_after, 
          loyalty_points_bonus, 
          loyalty_points_after_bonus
  FROM gaming_game_plays 
  JOIN gaming_game_manufacturers ON gaming_game_manufacturers.name=@game_manufacturer 
  JOIN gaming_cw_transactions ON gaming_cw_transactions.game_play_id=gaming_game_plays.game_play_id AND gaming_cw_transactions.transaction_ref=@transaction_ref
  JOIN gaming_payment_transaction_type ON gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id;
END root$$

DELIMITER ;
