-- ============================================================================
-- update_produto: arte_url/foto_url gravados DIRETO (sem COALESCE).
--
-- Antes: arte_url = COALESCE(p_arte_url, arte_url). Isso fazia "Trocar"
-- funcionar (URL nova é não-nula), mas "Remover" NÃO — o valor antigo
-- persistia. Como o form de Estoque SEMPRE manda o valor atual (carrega
-- p.arte_url/p.foto_url ao abrir e reenvia no save), o form é a fonte única
-- da verdade: gravar direto reflete trocar E remover.
--
-- Efeito no bot: resolverFotoProduto lê arte_url fresco a cada turno e valida
-- por HEAD antes de anexar → trocar a arte no cadastro troca a foto que o bot
-- envia (nos próximos envios); remover faz cair no fallback do bucket Start.
-- O upload da arte já grava no bucket Start (EstoquePage.uploadImagem).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_produto(
  p_id             uuid,
  p_nome_oficial   text,
  p_tag            text,
  p_cor_card       text,
  p_cor_texto      text,
  p_limite_estoque integer,
  p_grupo_id       uuid,
  p_box_size       text,
  p_box_qty_max    integer,
  p_peso           integer DEFAULT 300,
  p_preco          numeric DEFAULT NULL,
  p_emoji          text    DEFAULT NULL,
  p_arte_url       text    DEFAULT NULL,
  p_foto_url       text    DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.produtos SET
    nome_oficial   = p_nome_oficial,
    tag            = p_tag,
    cor_card       = p_cor_card,
    cor_texto      = p_cor_texto,
    limite_estoque = p_limite_estoque,
    grupo_id       = p_grupo_id,
    box_size       = p_box_size,
    box_qty_max    = p_box_qty_max,
    peso           = p_peso,
    preco          = COALESCE(p_preco, preco),
    emoji          = COALESCE(p_emoji, emoji),
    arte_url       = p_arte_url,   -- direto: form é a fonte da verdade
    foto_url       = p_foto_url    -- direto: permite trocar E remover
  WHERE id = p_id;
END $$;

GRANT EXECUTE ON FUNCTION public.update_produto(uuid,text,text,text,text,integer,uuid,text,integer,integer,numeric,text,text,text)
  TO authenticated;

NOTIFY pgrst, 'reload schema';
