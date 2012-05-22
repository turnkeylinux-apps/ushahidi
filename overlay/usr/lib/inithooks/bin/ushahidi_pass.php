<?php

class Auth {
	public function __construct($hash_method, $salt_pattern) {
        $config['hash_method'] = $hash_method;
		$config['salt_pattern'] = preg_split('/,\s*/', $salt_pattern);
		$this->config = $config;
    }

	public function hash($str) {
		return hash($this->config['hash_method'], $str);
	}

	public function hash_password($password) {
        $salt_count = count($this->config['salt_pattern']);
        $salt = substr($this->hash(uniqid(NULL, TRUE)), 0, $salt_count);

		$hash = $this->hash($salt.$password);
		$salt = str_split($salt, 1);
		$password = '';
		$last_offset = 0;

		foreach ($this->config['salt_pattern'] as $offset) {
			$part = substr($hash, 0, $offset - $last_offset);
			$hash = substr($hash, $offset - $last_offset);
			$password .= $part.array_shift($salt);
			$last_offset = $offset;
		}

		return $password.$hash;
	}
}

if(count($argv)!=2) die("usage: $argv[0] password\n");

// must be insync with ushahidi/application/config/auth.php
$salt_pattern = '3, 5, 6, 10, 24, 26, 35, 36, 37, 40';
$password = $argv[1];

$auth = new Auth('sha1', $salt_pattern);
print $auth->hash_password($password);

print "\n";
?>
