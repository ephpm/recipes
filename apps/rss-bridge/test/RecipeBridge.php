<?php

/** A minimal custom bridge, used by test.sh to check the /config drop-in path. */
class RecipeBridge extends BridgeAbstract
{
    const NAME = 'ePHPm Recipe Bridge';
    const URI = 'https://ephpm.dev/';
    const DESCRIPTION = 'Custom bridge installed from the config volume';
    const MAINTAINER = 'ephpm';
    const CACHE_TIMEOUT = 60;

    public function collectData()
    {
        $this->items[] = [
            'title' => 'Hello from ePHPm',
            'uri' => 'https://ephpm.dev/',
            'content' => 'Served by a custom bridge.',
            'uid' => 'ephpm-recipe-1',
        ];
    }
}
