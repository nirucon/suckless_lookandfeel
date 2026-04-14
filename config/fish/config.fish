source /usr/share/cachyos-fish-config/cachyos-config.fish

function fish_greeting
end

function update --description "Uppdatera system och AUR utan review"
    paru -Syu --skipreview
end
