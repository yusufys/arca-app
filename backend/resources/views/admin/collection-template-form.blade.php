@php
    $editing = $template !== null;
    $prefix = $editing ? 'template-'.$template->id : 'new';
    $restore = (string) old('_editing', '') === ($editing ? (string) $template->id : 'new');
@endphp
<form method="POST" action="{{ $editing ? '/admin/collection-templates/'.$template->id : '/admin/collection-templates' }}">
    @csrf
    <input type="hidden" name="_editing" value="{{ $editing ? $template->id : 'new' }}">
    <label for="{{ $prefix }}-slug">Stable catalog ID</label>
    <input id="{{ $prefix }}-slug" name="slug" @readonly($editing) required maxlength="100" pattern="[a-z0-9]+([_-][a-z0-9]+)*" value="{{ $restore ? old('slug') : ($template?->slug ?? '') }}">
    <label for="{{ $prefix }}-subtitle">Description</label>
    <input id="{{ $prefix }}-subtitle" name="subtitle" required maxlength="500" value="{{ $restore ? old('subtitle') : ($template?->subtitle ?? '') }}">
    <label for="{{ $prefix }}-order">Sort order (lower appears first)</label>
    <input id="{{ $prefix }}-order" name="sort_order" type="number" min="-100000" max="100000" required value="{{ $restore ? old('sort_order') : ($template?->sort_order ?? 0) }}">
    <label for="{{ $prefix }}-status">Status</label>
    <select id="{{ $prefix }}-status" name="is_active">
        <option value="0" @selected(! ($restore ? old('is_active') : $template?->is_active))>Draft</option>
        <option value="1" @selected($restore ? old('is_active') : $template?->is_active)>Active</option>
    </select>
    <label for="{{ $prefix }}-schema">Collection schema JSON</label>
    <textarea id="{{ $prefix }}-schema" name="schema_json" rows="16" required spellcheck="false">{{ $restore ? old('schema_json') : json_encode($schema, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) }}</textarea>
    <button type="submit">{{ $editing ? 'Save template' : 'Create template' }}</button>
</form>
