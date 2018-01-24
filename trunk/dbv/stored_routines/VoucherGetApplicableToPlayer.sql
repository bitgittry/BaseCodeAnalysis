DROP procedure IF EXISTS `VoucherGetApplicableToPlayer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `VoucherGetApplicableToPlayer`(clientStatID BIGINT)
BEGIN

  -- Added index non_expired

  CALL PlayerSelectionUpdatePlayerCacheVouchers(clientStatID);
  
  SELECT gaming_vouchers.voucher_id, gaming_vouchers.voucher_code, gaming_vouchers.name, gaming_vouchers.description, gaming_vouchers.player_selection_id,
	gaming_vouchers.activation_date, deactivation_date, gaming_vouchers.created_date, gaming_vouchers.last_updated_date, gaming_vouchers.is_active, gaming_vouchers.is_deleted
  FROM gaming_vouchers FORCE INDEX (non_expired)
  JOIN gaming_player_selections_player_cache AS cache ON gaming_vouchers.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID AND cache.player_in_selection=1
  LEFT JOIN gaming_voucher_instances ON gaming_vouchers.voucher_id=gaming_voucher_instances.voucher_id AND gaming_voucher_instances.client_stat_id=clientStatID
  WHERE gaming_vouchers.is_deleted = 0 AND gaming_vouchers.is_active=1 AND gaming_vouchers.activation_date<NOW() AND gaming_vouchers.deactivation_date>NOW() AND gaming_voucher_instances.client_stat_id IS NULL;
  
  
  SELECT gaming_vouchers.voucher_id, gaming_voucher_bonuses.bonus_rule_id
  FROM gaming_vouchers FORCE INDEX (non_expired)
  JOIN gaming_player_selections_player_cache AS cache ON gaming_vouchers.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID AND cache.player_in_selection=1
  LEFT JOIN gaming_voucher_instances ON gaming_vouchers.voucher_id=gaming_voucher_instances.voucher_id AND gaming_voucher_instances.client_stat_id=clientStatID
  JOIN gaming_voucher_bonuses ON gaming_vouchers.voucher_id=gaming_voucher_bonuses.voucher_id
  WHERE gaming_vouchers.is_deleted = 0 AND gaming_vouchers.is_active=1 AND gaming_vouchers.activation_date<NOW() AND gaming_vouchers.deactivation_date>NOW() AND gaming_voucher_instances.client_stat_id IS NULL;

END$$

DELIMITER ;

