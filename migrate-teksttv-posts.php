<?php
/**
 * Migrate per-post Tekst TV data from the streekomroep-wp theme (ACF) to the
 * teksttv-wp-plugin post meta model.
 *
 * Source (ACF meta, written by the theme + zw-ttvgpt):
 *   post_in_kabelkrant          -> _teksttv_active ('1')
 *   post_kabelkrant_content     -> _teksttv_content (wpautop'd HTML)
 *   post_kabelkrant_content_gpt -> _teksttv_ai_body (wpautop'd HTML, AI audit baseline)
 *
 * Deliberately NOT migrated (unused in production, verified 2026-08-04):
 *   post_kabelkrant_datum_uit, post_kabelkrant_dagen,
 *   post_kabelkrant_extra_afbeeldingen, teksttv_categorie_afbeelding.
 *
 * Internal whitespace (including newlines) is flattened to a single space
 * before wpautop(), so every post becomes exactly one <p>. Multi-paragraph
 * TV text was never intended; only 24 legacy posts had it.
 *
 * Both content fields get the identical transform so the plugin's AI-audit
 * page (trim-equality compare) classifies posts exactly like zw-ttvgpt's
 * audit did.
 *
 * Usage:
 *   wp eval-file migrate-teksttv-posts.php                   (dry run)
 *   wp eval-file migrate-teksttv-posts.php migrate           (write meta)
 *   wp eval-file migrate-teksttv-posts.php migrate overwrite (also overwrite existing _teksttv_content)
 *   wp eval-file migrate-teksttv-posts.php migrate limit=100 (only first 100 posts, for testing)
 */

if (!defined('ABSPATH') || !defined('WP_CLI')) {
    echo 'Run this with: wp eval-file migrate-teksttv-posts.php' . PHP_EOL;
    exit(1);
}

$cli_args = isset($args) && is_array($args) ? $args : [];
$do_migrate = in_array('migrate', $cli_args, true);
$overwrite = in_array('overwrite', $cli_args, true);
$limit = 0;
foreach ($cli_args as $cli_arg) {
    if (preg_match('/^limit=(\d+)$/', $cli_arg, $m)) {
        $limit = (int) $m[1];
    } elseif (!in_array($cli_arg, ['migrate', 'overwrite'], true)) {
        WP_CLI::error(sprintf('Unknown argument: %s', $cli_arg));
    }
}

if (!$do_migrate) {
    WP_CLI::log('DRY RUN - no changes will be made. Add "migrate" to write the meta.');
}

global $wpdb;

// Candidates: any non-trashed post flagged for the kabelkrant with actual
// content. This also includes custom post statuses.
$sql = sprintf(
    <<<'SQL'
        SELECT DISTINCT p.ID
        FROM %s p
        INNER JOIN %s flag
            ON flag.post_id = p.ID
            AND flag.meta_key = 'post_in_kabelkrant'
            AND flag.meta_value = '1'
        INNER JOIN %s content
            ON content.post_id = p.ID
            AND content.meta_key = 'post_kabelkrant_content'
            AND TRIM(content.meta_value) <> ''
        WHERE p.post_type = 'post'
            AND p.post_status <> 'trash'
        ORDER BY p.ID ASC
        SQL,
    $wpdb->posts,
    $wpdb->postmeta,
    $wpdb->postmeta
);
if ($limit > 0) {
    $sql .= ' LIMIT ' . $limit;
}

$wpdb->last_error = '';
// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared -- table names come from $wpdb; the remaining SQL is static and LIMIT is an integer.
$post_ids = array_map('intval', $wpdb->get_col($sql));
if ($wpdb->last_error !== '') {
    WP_CLI::error('Candidate query failed: ' . $wpdb->last_error);
}

WP_CLI::log(sprintf('Found %d candidate posts.', count($post_ids)));

$stats = [
    'content_migrated' => 0,
    'skipped_existing' => 0,
    'active_changes' => 0,
    'ai_changes' => 0,
    'ai_removed' => 0,
    'with_ai_baseline' => 0,
    'ai_unmodified' => 0,
];
$batch_size = 500;

/**
 * Set a post-meta value only when it differs, and verify failed writes.
 *
 * @return bool Whether a write is or would be needed.
 */
$set_post_meta = static function (int $post_id, string $meta_key, string $value) use ($do_migrate): bool {
    $exists = metadata_exists('post', $post_id, $meta_key);
    $current = get_post_meta($post_id, $meta_key, true);
    if ($exists && $current === $value) {
        return false;
    }

    if (!$do_migrate) {
        return true;
    }

    $result = update_post_meta($post_id, $meta_key, wp_slash($value));
    if ($result === false) {
        // A concurrent identical write also returns false, so verify the result
        // before treating it as an error.
        wp_cache_delete($post_id, 'post_meta');
        $stored = get_post_meta($post_id, $meta_key, true);
        if (!metadata_exists('post', $post_id, $meta_key) || $stored !== $value) {
            WP_CLI::error(sprintf('Failed to write %s for post %d.', $meta_key, $post_id));
        }
    }

    return true;
};

/**
 * Delete post meta when present, and verify failed deletes.
 *
 * @return bool Whether a delete is or would be needed.
 */
$delete_post_meta = static function (int $post_id, string $meta_key) use ($do_migrate): bool {
    if (!metadata_exists('post', $post_id, $meta_key)) {
        return false;
    }

    if (!$do_migrate) {
        return true;
    }

    $result = delete_post_meta($post_id, $meta_key);
    if ($result === false) {
        wp_cache_delete($post_id, 'post_meta');
        if (metadata_exists('post', $post_id, $meta_key)) {
            WP_CLI::error(sprintf('Failed to delete %s for post %d.', $meta_key, $post_id));
        }
    }

    return true;
};

foreach (array_chunk($post_ids, $batch_size) as $batch) {
    // Load all source and target meta for this batch in one query. A runtime
    // flush below releases local memory without clearing a persistent cache.
    $wpdb->last_error = '';
    update_meta_cache('post', $batch);
    if ($wpdb->last_error !== '') {
        WP_CLI::error('Meta prefetch failed: ' . $wpdb->last_error);
    }

    foreach ($batch as $post_id) {
        $content = trim(preg_replace('/\s+/', ' ', (string) get_post_meta($post_id, 'post_kabelkrant_content', true)));
        $gpt = trim(preg_replace('/\s+/', ' ', (string) get_post_meta($post_id, 'post_kabelkrant_content_gpt', true)));

        $content_html = wpautop($content);
        $gpt_html = $gpt !== '' ? wpautop($gpt) : '';

        if ($gpt_html !== '') {
            $stats['with_ai_baseline']++;
            if (trim($gpt_html) === trim($content_html)) {
                $stats['ai_unmodified']++;
            }
        }

        $existing = get_post_meta($post_id, '_teksttv_content', true);
        $has_existing_content = is_string($existing) && trim($existing) !== '';
        $skip_content = !$overwrite && $has_existing_content;

        if ($skip_content) {
            $stats['skipped_existing']++;

            // Preserve deliberate target-plugin choices, but repair fields that
            // can be missing after an interrupted migration.
            $active_exists = metadata_exists('post', $post_id, '_teksttv_active');
            $active = get_post_meta($post_id, '_teksttv_active', true);
            if (
                (!$active_exists || !in_array($active, ['0', '1'], true))
                && $set_post_meta($post_id, '_teksttv_active', '1')
            ) {
                $stats['active_changes']++;
            }

            $ai_exists = metadata_exists('post', $post_id, '_teksttv_ai_body');
            $existing_ai = get_post_meta($post_id, '_teksttv_ai_body', true);
            if (
                $gpt_html !== '' && (!$ai_exists || trim((string) $existing_ai) === '')
                && $set_post_meta($post_id, '_teksttv_ai_body', $gpt_html)
            ) {
                $stats['ai_changes']++;
            }

            continue;
        }

        $stats['content_migrated']++;
        if ($set_post_meta($post_id, '_teksttv_active', '1')) {
            $stats['active_changes']++;
        }
        $set_post_meta($post_id, '_teksttv_content', $content_html);
        if ($gpt_html !== '') {
            if ($set_post_meta($post_id, '_teksttv_ai_body', $gpt_html)) {
                $stats['ai_changes']++;
            }
        } elseif ($delete_post_meta($post_id, '_teksttv_ai_body')) {
            $stats['ai_removed']++;
        }
    }

    // Core's runtime flush falls back to wp_cache_flush(). Only use it when
    // there is no external cache, so an older persistent-cache drop-in can
    // never turn this into a site-wide flush.
    if (!wp_using_ext_object_cache() && function_exists('wp_cache_flush_runtime')) {
        wp_cache_flush_runtime();
    }

    WP_CLI::log(sprintf(
        '  ... %d/%d processed',
        min($stats['content_migrated'] + $stats['skipped_existing'], count($post_ids)),
        count($post_ids)
    ));
}

WP_CLI::log('');
WP_CLI::log(sprintf('%s content: %d', $do_migrate ? 'Migrated' : 'Would migrate', $stats['content_migrated']));
WP_CLI::log(sprintf('Preserved existing _teksttv_content: %d', $stats['skipped_existing']));
WP_CLI::log(sprintf('%s _teksttv_active: %d', $do_migrate ? 'Set/repaired' : 'Would set/repair', $stats['active_changes']));
WP_CLI::log(sprintf('%s AI baselines: %d', $do_migrate ? 'Set/repaired' : 'Would set/repair', $stats['ai_changes']));
WP_CLI::log(sprintf('%s stale AI baselines: %d', $do_migrate ? 'Removed' : 'Would remove', $stats['ai_removed']));
WP_CLI::log(sprintf('Source posts with AI baseline: %d', $stats['with_ai_baseline']));
WP_CLI::log(sprintf('  of which unmodified vs content (audit check): %d', $stats['ai_unmodified']));

if ($do_migrate) {
    WP_CLI::success('Migration complete.');
} else {
    WP_CLI::success('Dry run complete. Add "migrate" to write the meta.');
}
