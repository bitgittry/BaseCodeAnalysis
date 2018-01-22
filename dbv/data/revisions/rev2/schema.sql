CREATE TABLE  `accounting_dc_note_types` (
  `sb_bet_id` bigint(20) NOT NULL,
  `max_sb_bet_single_id` bigint(20) DEFAULT NULL,
  `max_sb_bet_multiple_id` bigint(20) DEFAULT NULL,
  `max_sb_bet_multiple_single_id` bigint(20) DEFAULT NULL,
  `min_game_round_id` bigint(20) DEFAULT NULL,
  `max_game_round_id` bigint(20) DEFAULT NULL,
  `max_game_play_sb_id` bigint(20) DEFAULT NULL,
  `min_game_play_sb_id` bigint(20) DEFAULT NULL,
  `max_game_play_bonus_instance_id` bigint(20) DEFAULT NULL, asf sfsfsdfsdfsdfasdf
  PRIMARY KEY (`sb_bet_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

ALTER TABLE `accounting_dc_notes` 
   ADD COLUMN `lock_uuid` VARCHAR(45) NULL AFTER `is_portal`,
   ADD INDEX `uuid` (`lock_uuid` ASC);