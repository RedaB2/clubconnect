alter table club_private.clubs
    add column "secondaryHex" text not null default '#31675D'
    check ("secondaryHex" ~ '^#[0-9a-fA-F]{6}$');

create or replace function club_private.save_club(c text, entry jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
    perform club_private.require_member(c, true);
    update club_private.clubs set
        name = trim(entry->>'name'),
        "fullName" = trim(entry->>'fullName'),
        about = entry->>'about',
        "accentHex" = entry->>'accentHex',
        -- Older builds send only the primary color. Preserve the saved secondary color.
        "secondaryHex" = coalesce(entry->>'secondaryHex', "secondaryHex"),
        "logoData" = entry->>'logoData'
    where id = c;
end $$;
