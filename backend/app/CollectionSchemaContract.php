<?php

namespace App;

use Illuminate\Validation\ValidationException;
use stdClass;

/** Validates the deliberately small JSON Schema vocabulary used by collection-v1.json. */
class CollectionSchemaContract
{
    public function schema(int $version = 2): array
    {
        return json_decode(file_get_contents(resource_path('contracts/collection-v'.($version === 2 ? '2' : '1').'.json')), true, 512, JSON_THROW_ON_ERROR);
    }

    public function validate(mixed $document): array
    {
        $json = json_encode($document, JSON_THROW_ON_ERROR);
        if (strlen($json) > $this->schema()['x-arca-max-document-bytes']) {
            throw ValidationException::withMessages(['schema' => 'The collection schema is too large.']);
        }
        $errors = $this->errors(json_decode($json, false, 512, JSON_THROW_ON_ERROR), $this->schema(), 'schema');
        if ($errors !== []) {
            throw ValidationException::withMessages($errors);
        }

        return json_decode($json, true, 512, JSON_THROW_ON_ERROR);
    }

    /** @return array<string, string> */
    private function errors(mixed $value, array $rule, string $path): array
    {
        $errors = [];
        $fail = function (string $message) use (&$errors, $path): void {
            $errors[$path] = $message;
        };
        $type = $rule['type'] ?? null;
        $validType = match ($type) {
            'object' => $value instanceof stdClass,
            'array' => is_array($value),
            'string' => is_string($value),
            'boolean' => is_bool($value),
            null => true,
            default => false,
        };
        if (! $validType) {
            return [$path => "Expected {$type}."];
        }
        if (isset($rule['enum']) && ! in_array($value, $rule['enum'], true)) {
            $fail('This value is not supported.');
        }
        if (array_key_exists('const', $rule) && $value !== $rule['const']) {
            $fail('This value is not allowed here.');
        }
        if (is_string($value)) {
            $length = mb_strlen($value);
            if ($length < ($rule['minLength'] ?? 0) || $length > ($rule['maxLength'] ?? PHP_INT_MAX)) {
                $fail('The text length is outside the allowed range.');
            }
            if (isset($rule['pattern']) && ! preg_match('~'.$rule['pattern'].'~u', $value)) {
                $fail('The text has an invalid format or is blank.');
            }
        }
        if ($value instanceof stdClass) {
            foreach ($rule['required'] ?? [] as $key) {
                if (! property_exists($value, $key)) {
                    $errors[$path.'.'.$key] = 'This property is required.';
                }
            }
            foreach (get_object_vars($value) as $key => $child) {
                if (isset($rule['properties'][$key])) {
                    $errors += $this->errors($child, $rule['properties'][$key], $path.'.'.$key);
                } elseif (($rule['additionalProperties'] ?? true) === false) {
                    $errors[$path.'.'.$key] = 'This property is not supported.';
                }
            }
        }
        if (is_array($value)) {
            if (count($value) < ($rule['minItems'] ?? 0) || count($value) > ($rule['maxItems'] ?? PHP_INT_MAX)) {
                $fail('The number of items is outside the allowed range.');
            }
            if (($rule['uniqueItems'] ?? false) && count(array_unique(array_map(fn ($item) => json_encode($item), $value))) !== count($value)) {
                $fail('Items must be unique.');
            }
            foreach ($value as $index => $child) {
                if (isset($rule['items'])) {
                    $errors += $this->errors($child, $rule['items'], $path.'.'.$index);
                }
            }
            if (isset($rule['contains'])) {
                $matches = count(array_filter($value, fn ($item) => $this->errors($item, $rule['contains'], $path) === []));
                if ($matches < ($rule['minContains'] ?? 1) || $matches > ($rule['maxContains'] ?? PHP_INT_MAX)) {
                    $fail('Only one primary title field is allowed.');
                }
            }
        }
        foreach ($rule['allOf'] ?? [] as $part) {
            $errors += $this->errors($value, $part, $path);
        }
        if (isset($rule['if'])) {
            $branch = $this->errors($value, $rule['if'], $path) === [] ? 'then' : 'else';
            $errors += $this->errors($value, $rule[$branch] ?? [], $path);
        }

        return $errors;
    }
}
