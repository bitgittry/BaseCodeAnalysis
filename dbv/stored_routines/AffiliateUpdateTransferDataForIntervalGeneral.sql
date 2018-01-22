DROP procedure IF EXISTS `AffiliateUpdateTransferDataForIntervalGeneral`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `AffiliateUpdateTransferDataForIntervalGeneral`(queryDateIntervalID BIGINT, OUT statusCode INT)
BEGIN
  -- To test
  DECLARE procVersion VARCHAR(30) DEFAULT 'Type1';

  SELECT value_string INTO procVersion FROM gaming_settings WHERE `name`='AFFILIATE_UPDATE_TRANFER_DATA_VERSION';
 
  CASE procVersion
    WHEN 'Type1' THEN
      BEGIN
		CALL AffiliateUpdateTransferDataForInterval(queryDateIntervalID, statusCode);
      END;
	WHEN 'Type2' THEN
      BEGIN
		CALL AffiliateUpdateTransferDataForIntervalType2(queryDateIntervalID, statusCode);
      END;
	WHEN 'Type3' THEN
      BEGIN
		CALL AffiliateUpdateTransferDataForIntervalType3(queryDateIntervalID, statusCode);
      END;
	WHEN 'Type4MyAffiliate' THEN
      BEGIN
		CALL AffiliateUpdateTransferDataForIntervalType4MyAffiliate(queryDateIntervalID, statusCode);
      END;
  END CASE;

END$$

DELIMITER ;

