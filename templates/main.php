<?php
/** @var \OCP\IL10N $l */
/** @var array $_ */
?>
<nav id="app-navigation" aria-label="PriNotes navigation">
    <div id="prinotes-nav" data-user="<?= $_['user_id'] ?? '' ?>"></div>
</nav>
<div id="app-content">
    <div id="prinotes-content" style="height:100%;display:flex;flex-direction:column;"></div>
</div>
