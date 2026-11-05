<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Suggested Collections · Arca Admin</title>
    <style>
        body { font: 16px system-ui,sans-serif; color:#17202e; background:#f4f6fa; margin:0; }
        main { max-width:1000px; margin:40px auto; padding:0 24px; }
        section,details { background:white; border:1px solid #d7dde6; border-radius:12px; padding:24px; margin:20px 0; }
        label { display:block; margin:16px 0 6px; font-weight:600; }
        input,textarea,select { box-sizing:border-box; width:100%; border:1px solid #aeb9c8; border-radius:6px; padding:10px; font:inherit; }
        textarea { font:13px ui-monospace,monospace; }
        button { margin-top:20px; background:#334fc0; color:white; border:0; padding:12px 20px; border-radius:6px; font:inherit; cursor:pointer; }
        summary { cursor:pointer; font-weight:600; } a { color:#334fc0; } .notice { padding:16px; background:#e2f4e7; } .error { color:#a11b30; }
    </style>
</head>
<body><main>
    <a href="/admin">← System administration</a>
    <h1>Suggested collections</h1>
    <p>Create a draft, edit its schema, then set it to Active. Active templates appear in apps on their next refresh. Existing user collections keep their own copy.</p>
    <p>The <a href="/api/v1/collection-schema">version 1 JSON contract</a> validates every save. Use field types listed there. Select fields need nonblank, unique options. Only one short text field can be the primary title. To remove a suggestion, set it to Draft.</p>
    @if(session('status'))<p class="notice">{{ session('status') }}</p>@endif
    @if($errors->any())<div class="error" role="alert"><p>The template was not saved:</p><ul>@foreach($errors->all() as $error)<li>{{ $error }}</li>@endforeach</ul></div>@endif
    <section>
        <h2>New template</h2>
        @include('admin.collection-template-form', ['template' => null, 'schema' => $example])
    </section>
    <h2>Catalog ({{ $templates->count() }})</h2>
    @forelse($templates as $template)
        <details @if((string) old('_editing') === (string) $template->id) open @endif><summary>{{ $template->schema_definition['name'] }} · {{ $template->is_active ? 'Active' : 'Draft' }} · {{ $template->slug }}</summary>
            @include('admin.collection-template-form', ['schema' => $template->schema_definition])
        </details>
    @empty<p>No templates yet. Create one above or run the catalog seeder.</p>@endforelse
</main></body>
</html>
