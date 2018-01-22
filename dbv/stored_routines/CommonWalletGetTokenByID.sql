DROP procedure IF EXISTS `CommonWalletGetTokenByID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletGetTokenByID`(cwTokenID bigint, gameSessionIdOverride bigint)
BEGIN

  IF(gameSessionIdOverride = -1) THEN
    SELECT cw_token_id, game_manufacturer_id, token_key, client_stat_id, game_session_id, created_date, expiry_date 
    FROM gaming_cw_tokens WHERE cw_token_id=cwTokenID;
  ELSE
    SELECT cw_token_id, game_manufacturer_id, token_key, client_stat_id, game_session_id, created_date, expiry_date
    FROM gaming_cw_tokens WHERE game_session_id=gameSessionIdOverride
    ORDER BY cw_token_id DESC
    LIMIT 1;
  END IF;
  
END$$

DELIMITER ;