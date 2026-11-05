<?php

namespace App\Http\Controllers;

use App\CollectionSchemaContract;
use App\Models\CollectionTemplate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Illuminate\View\View;
use JsonException;

class AdminCollectionTemplateController extends Controller
{
    public function index(): View
    {
        return view('admin.collection-templates', [
            'templates' => CollectionTemplate::orderBy('sort_order')->orderBy('slug')->get(),
            'example' => ['name' => 'Equipment', 'iconName' => 'folder.fill', 'colorHex' => '#2B5B84', 'fields' => [
                ['label' => 'Name', 'type' => 'short_text', 'isRequired' => true, 'isPrimaryTitle' => true],
            ]],
        ]);
    }

    public function store(Request $request, CollectionSchemaContract $contract): JsonResponse|RedirectResponse
    {
        $template = CollectionTemplate::create($this->validated($request, $contract));

        return $this->saved($request, $template, 201);
    }

    public function update(Request $request, CollectionTemplate $template, CollectionSchemaContract $contract): JsonResponse|RedirectResponse
    {
        $template->update($this->validated($request, $contract, $template));

        return $this->saved($request, $template);
    }

    private function validated(Request $request, CollectionSchemaContract $contract, ?CollectionTemplate $template = null): array
    {
        $data = $request->validate([
            'slug' => ['required', 'string', 'max:100', 'regex:/^[a-z0-9]+(?:[_-][a-z0-9]+)*$/', Rule::unique('collection_templates', 'slug')->ignore($template), Rule::when($template !== null, [Rule::in([$template?->slug])])],
            'subtitle' => ['required', 'string', 'max:500'],
            'schema_json' => ['required', 'string', 'max:262144'],
            'is_active' => ['required', 'boolean'],
            'sort_order' => ['required', 'integer', 'between:-100000,100000'],
        ]);
        try {
            $document = json_decode($data['schema_json'], false, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException) {
            throw ValidationException::withMessages(['schema_json' => 'Enter one valid JSON object.']);
        }

        return [
            'slug' => $data['slug'],
            'subtitle' => $data['subtitle'],
            'schema_definition' => $contract->validate($document),
            'is_active' => $request->boolean('is_active'),
            'sort_order' => $data['sort_order'],
        ];
    }

    private function saved(Request $request, CollectionTemplate $template, int $status = 200): JsonResponse|RedirectResponse
    {
        if ($request->expectsJson()) {
            return response()->json(['template' => $template->catalogEntry(), 'is_active' => $template->is_active], $status);
        }

        return redirect()->route('admin.collection-templates')->with('status', 'Collection template saved. Active templates are available to apps immediately.');
    }
}
