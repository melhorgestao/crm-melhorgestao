export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.4"
  }
  public: {
    Tables: {
      comissoes: {
        Row: {
          data_criacao: string | null
          data_pagamento: string | null
          id: string
          pedido_id: string | null
          produto: string
          representante_id: string | null
          status: string | null
          valor_fixo: number
        }
        Insert: {
          data_criacao?: string | null
          data_pagamento?: string | null
          id?: string
          pedido_id?: string | null
          produto: string
          representante_id?: string | null
          status?: string | null
          valor_fixo: number
        }
        Update: {
          data_criacao?: string | null
          data_pagamento?: string | null
          id?: string
          pedido_id?: string | null
          produto?: string
          representante_id?: string | null
          status?: string | null
          valor_fixo?: number
        }
        Relationships: [
          {
            foreignKeyName: "comissoes_pedido_id_fkey"
            columns: ["pedido_id"]
            isOneToOne: false
            referencedRelation: "pedidos"
            referencedColumns: ["id"]
          },
        ]
      }
      config_comissao_produto: {
        Row: {
          ativo: boolean | null
          id: string
          produto_tag: string
          valor_comissao: number
        }
        Insert: {
          ativo?: boolean | null
          id?: string
          produto_tag: string
          valor_comissao: number
        }
        Update: {
          ativo?: boolean | null
          id?: string
          produto_tag?: string
          valor_comissao?: number
        }
        Relationships: []
      }
      configuracoes: {
        Row: {
          chave: string
          id: string
          updated_at: string | null
          valor: string | null
        }
        Insert: {
          chave: string
          id?: string
          updated_at?: string | null
          valor?: string | null
        }
        Update: {
          chave?: string
          id?: string
          updated_at?: string | null
          valor?: string | null
        }
        Relationships: []
      }
      contatos: {
        Row: {
          bairro: string | null
          canal_atual: string | null
          canal_origem: string
          cep: string | null
          cidade: string | null
          cidade_uf: string | null
          complemento: string | null
          cpf: string | null
          created_at: string
          endereco: string | null
          id: string
          instancia_id: string | null
          nome: string
          tag_kanban: string | null
          tag_kanban_ate: string | null
          observacao: string | null
          representante_id: string | null
          status_kanban: string | null
          telefone: string | null
          uf: string | null
          ultima_venda_em: string | null
          updated_at: string
          utm_origem: string | null
        }
        Insert: {
          bairro?: string | null
          canal_atual?: string | null
          canal_origem: string
          cep?: string | null
          cidade?: string | null
          cidade_uf?: string | null
          complemento?: string | null
          cpf?: string | null
          created_at?: string
          endereco?: string | null
          id?: string
          instancia_id?: string | null
          nome: string
          tag_kanban?: string | null
          tag_kanban_ate?: string | null
          observacao?: string | null
          representante_id?: string | null
          status_kanban?: string | null
          telefone?: string | null
          uf?: string | null
          ultima_venda_em?: string | null
          updated_at?: string
          utm_origem?: string | null
        }
        Update: {
          bairro?: string | null
          canal_atual?: string | null
          canal_origem?: string
          cep?: string | null
          cidade?: string | null
          cidade_uf?: string | null
          complemento?: string | null
          cpf?: string | null
          created_at?: string
          endereco?: string | null
          id?: string
          instancia_id?: string | null
          nome?: string
          tag_kanban?: string | null
          tag_kanban_ate?: string | null
          observacao?: string | null
          representante_id?: string | null
          status_kanban?: string | null
          telefone?: string | null
          uf?: string | null
          ultima_venda_em?: string | null
          updated_at?: string
          utm_origem?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contatos_instancia_id_fkey"
            columns: ["instancia_id"]
            isOneToOne: false
            referencedRelation: "instancias"
            referencedColumns: ["id"]
          },
        ]
      }
      estoque_movimentacoes: {
        Row: {
          created_at: string
          data: string
          id: string
          lote_id: string | null
          observacao: string | null
          pedido_id: string | null
          pedido_item_id: string | null
          posse: string | null
          produto_id: string
          quantidade: number
          tipo: string
          uf_origem: string | null
        }
        Insert: {
          created_at?: string
          data?: string
          id?: string
          lote_id?: string | null
          observacao?: string | null
          pedido_id?: string | null
          pedido_item_id?: string | null
          posse?: string | null
          produto_id: string
          quantidade: number
          tipo: string
          uf_origem?: string | null
        }
        Update: {
          created_at?: string
          data?: string
          id?: string
          lote_id?: string | null
          observacao?: string | null
          pedido_id?: string | null
          pedido_item_id?: string | null
          posse?: string | null
          produto_id?: string
          quantidade?: number
          tipo?: string
          uf_origem?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "estoque_movimentacoes_lote_id_fkey"
            columns: ["lote_id"]
            isOneToOne: false
            referencedRelation: "lotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "estoque_movimentacoes_pedido_id_fkey"
            columns: ["pedido_id"]
            isOneToOne: false
            referencedRelation: "pedidos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "estoque_movimentacoes_pedido_item_id_fkey"
            columns: ["pedido_item_id"]
            isOneToOne: false
            referencedRelation: "pedido_itens"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "estoque_movimentacoes_produto_id_fkey"
            columns: ["produto_id"]
            isOneToOne: false
            referencedRelation: "produtos"
            referencedColumns: ["id"]
          },
        ]
      }
      estoque_snapshot: {
        Row: {
          entrada: number | null
          estado: string | null
          id: string
          prod_id: string | null
          prod_nome: string | null
          saida: number | null
          saldo: number | null
          updated_at: string | null
        }
        Insert: {
          entrada?: number | null
          estado?: string | null
          id?: string
          prod_id?: string | null
          prod_nome?: string | null
          saida?: number | null
          saldo?: number | null
          updated_at?: string | null
        }
        Update: {
          entrada?: number | null
          estado?: string | null
          id?: string
          prod_id?: string | null
          prod_nome?: string | null
          saida?: number | null
          saldo?: number | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "estoque_snapshot_prod_id_fkey"
            columns: ["prod_id"]
            isOneToOne: false
            referencedRelation: "produtos"
            referencedColumns: ["id"]
          },
        ]
      }
      estoque_snapshots: {
        Row: {
          data_snapshot: string | null
          id: string
          observacao: string | null
          produto_id: string | null
          saldo: number
          uf: string
        }
        Insert: {
          data_snapshot?: string | null
          id?: string
          observacao?: string | null
          produto_id?: string | null
          saldo: number
          uf: string
        }
        Update: {
          data_snapshot?: string | null
          id?: string
          observacao?: string | null
          produto_id?: string | null
          saldo?: number
          uf?: string
        }
        Relationships: [
          {
            foreignKeyName: "estoque_snapshots_produto_id_fkey"
            columns: ["produto_id"]
            isOneToOne: false
            referencedRelation: "produtos"
            referencedColumns: ["id"]
          },
        ]
      }
      estoque_ufs: {
        Row: {
          created_at: string | null
          uf: string
        }
        Insert: {
          created_at?: string | null
          uf: string
        }
        Update: {
          created_at?: string | null
          uf?: string
        }
        Relationships: []
      }
      financeiro: {
        Row: {
          canal: string | null
          categoria: string | null
          created_at: string
          data: string
          descricao: string | null
          id: string
          quantidade: number | null
          tipo: string
          valor: number
        }
        Insert: {
          canal?: string | null
          categoria?: string | null
          created_at?: string
          data?: string
          descricao?: string | null
          id?: string
          quantidade?: number | null
          tipo: string
          valor: number
        }
        Update: {
          canal?: string | null
          categoria?: string | null
          created_at?: string
          data?: string
          descricao?: string | null
          id?: string
          quantidade?: number | null
          tipo?: string
          valor?: number
        }
        Relationships: []
      }
      follow_up: {
        Row: {
          contato_id: string
          created_at: string
          data_envio: string | null
          id: string
          mensagem: string | null
          status: string | null
          tipo: string | null
        }
        Insert: {
          contato_id: string
          created_at?: string
          data_envio?: string | null
          id?: string
          mensagem?: string | null
          status?: string | null
          tipo?: string | null
        }
        Update: {
          contato_id?: string
          created_at?: string
          data_envio?: string | null
          id?: string
          mensagem?: string | null
          status?: string | null
          tipo?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "follow_up_contato_id_fkey"
            columns: ["contato_id"]
            isOneToOne: false
            referencedRelation: "contatos"
            referencedColumns: ["id"]
          },
        ]
      }
      instancias: {
        Row: {
          acesso_kanban: string | null
          ativo: boolean
          created_at: string
          dono_tipo: string | null
          id: string
          is_default_base: boolean | null
          nome: string
          numero_final: string | null
          representante_user_id: string | null
          tipo: string
        }
        Insert: {
          acesso_kanban?: string | null
          ativo?: boolean
          created_at?: string
          dono_tipo?: string | null
          id?: string
          is_default_base?: boolean | null
          nome: string
          numero_final?: string | null
          representante_user_id?: string | null
          tipo: string
        }
        Update: {
          acesso_kanban?: string | null
          ativo?: boolean
          created_at?: string
          dono_tipo?: string | null
          id?: string
          is_default_base?: boolean | null
          nome?: string
          numero_final?: string | null
          representante_user_id?: string | null
          tipo?: string
        }
        Relationships: []
      }
      lancamentos_socios: {
        Row: {
          canal: string | null
          contato_id: string | null
          created_at: string
          criado_por: string | null
          data: string
          descricao: string | null
          id: string
          locked_at: string | null
          modalidade: string | null
          pedido_id: string | null
          produto_id: string | null
          quantidade: number | null
          realizado: boolean
          realizado_em: string | null
          snapshot_saldo_a: number | null
          snapshot_saldo_v: number | null
          socio: string
          status_pagamento: string | null
          tipo: string
          transferencia_direcao: string | null
          uf_postagem: string | null
          valor: number
        }
        Insert: {
          canal?: string | null
          contato_id?: string | null
          created_at?: string
          criado_por?: string | null
          data?: string
          descricao?: string | null
          id?: string
          locked_at?: string | null
          modalidade?: string | null
          pedido_id?: string | null
          produto_id?: string | null
          quantidade?: number | null
          realizado?: boolean
          realizado_em?: string | null
          snapshot_saldo_a?: number | null
          snapshot_saldo_v?: number | null
          socio: string
          status_pagamento?: string | null
          tipo: string
          transferencia_direcao?: string | null
          uf_postagem?: string | null
          valor: number
        }
        Update: {
          canal?: string | null
          contato_id?: string | null
          created_at?: string
          criado_por?: string | null
          data?: string
          descricao?: string | null
          id?: string
          locked_at?: string | null
          modalidade?: string | null
          pedido_id?: string | null
          produto_id?: string | null
          quantidade?: number | null
          realizado?: boolean
          realizado_em?: string | null
          snapshot_saldo_a?: number | null
          snapshot_saldo_v?: number | null
          socio?: string
          status_pagamento?: string | null
          tipo?: string
          transferencia_direcao?: string | null
          uf_postagem?: string | null
          valor?: number
        }
        Relationships: [
          {
            foreignKeyName: "lancamentos_socios_contato_id_fkey"
            columns: ["contato_id"]
            isOneToOne: false
            referencedRelation: "contatos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lancamentos_socios_pedido_id_fkey"
            columns: ["pedido_id"]
            isOneToOne: false
            referencedRelation: "pedidos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lancamentos_socios_produto_id_fkey"
            columns: ["produto_id"]
            isOneToOne: false
            referencedRelation: "produtos"
            referencedColumns: ["id"]
          },
        ]
      }
      log_atividades: {
        Row: {
          acao: string
          created_at: string
          detalhe: string | null
          id: string
          registro_id: string | null
          tabela_afetada: string | null
          usuario: string
        }
        Insert: {
          acao: string
          created_at?: string
          detalhe?: string | null
          id?: string
          registro_id?: string | null
          tabela_afetada?: string | null
          usuario: string
        }
        Update: {
          acao?: string
          created_at?: string
          detalhe?: string | null
          id?: string
          registro_id?: string | null
          tabela_afetada?: string | null
          usuario?: string
        }
        Relationships: []
      }
      lotes: {
        Row: {
          created_at: string
          data_producao: string
          id: string
          lote_codigo: string
          produto_id: string
          quantidade_atual: number
          quantidade_inicial: number
          representante_id: string | null
          uf: string
        }
        Insert: {
          created_at?: string
          data_producao?: string
          id?: string
          lote_codigo: string
          produto_id: string
          quantidade_atual: number
          quantidade_inicial: number
          representante_id?: string | null
          uf: string
        }
        Update: {
          created_at?: string
          data_producao?: string
          id?: string
          lote_codigo?: string
          produto_id?: string
          quantidade_atual?: number
          quantidade_inicial?: number
          representante_id?: string | null
          uf?: string
        }
        Relationships: [
          {
            foreignKeyName: "lotes_produto_id_fkey"
            columns: ["produto_id"]
            isOneToOne: false
            referencedRelation: "produtos"
            referencedColumns: ["id"]
          },
        ]
      }
      metas_mensais: {
        Row: {
          ano: number
          created_at: string
          id: string
          mes: number
          user_id: string
          valor: number
        }
        Insert: {
          ano: number
          created_at?: string
          id?: string
          mes: number
          user_id: string
          valor?: number
        }
        Update: {
          ano?: number
          created_at?: string
          id?: string
          mes?: number
          user_id?: string
          valor?: number
        }
        Relationships: []
      }
      notificacoes: {
        Row: {
          created_at: string | null
          id: string
          lido: boolean | null
          mensagem: string | null
          tipo: string
          titulo: string
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          lido?: boolean | null
          mensagem?: string | null
          tipo: string
          titulo: string
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          lido?: boolean | null
          mensagem?: string | null
          tipo?: string
          titulo?: string
          user_id?: string | null
        }
        Relationships: []
      }
      pedido_itens: {
        Row: {
          created_at: string
          id: string
          nome_oficial: string | null
          pedido_id: string
          preco: number | null
          produto_id: string
          quantidade: number
        }
        Insert: {
          created_at?: string
          id?: string
          nome_oficial?: string | null
          pedido_id: string
          preco?: number | null
          produto_id: string
          quantidade: number
        }
        Update: {
          created_at?: string
          id?: string
          nome_oficial?: string | null
          pedido_id?: string
          preco?: number | null
          produto_id?: string
          quantidade?: number
        }
        Relationships: [
          {
            foreignKeyName: "pedido_itens_pedido_id_fkey"
            columns: ["pedido_id"]
            isOneToOne: false
            referencedRelation: "pedidos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pedido_itens_produto_id_fkey"
            columns: ["produto_id"]
            isOneToOne: false
            referencedRelation: "produtos"
            referencedColumns: ["id"]
          },
        ]
      }
      pedidos: {
        Row: {
          altura_caixa: number | null
          box_size: string | null
          canal: string | null
          codigo_rastreio: string | null
          complemento: string | null
          comprimento_caixa: number | null
          contato_id: string | null
          created_at: string
          criado_por: string | null
          data: string
          data_pago: string | null
          desconto_total: number | null
          endereco_entrega: string | null
          entrega_em_maos: boolean | null
          estoque_debitado: boolean | null
          estoque_processado: boolean | null
          etiqueta_codigo: string | null
          etiqueta_paga: boolean | null
          etiqueta_url: string | null
          etiqueta_valor: number | null
          formato_caixa: string | null
          gateway_etiqueta: string | null
          id: string
          instancia_id: string | null
          is_free: boolean | null
          largura_caixa: number | null
          locked_at: string | null
          modalidade: string | null
          obs: string | null
          observacao: string | null
          order_number: number
          peso_envio: number | null
          preco_unitario: number | null
          produto: string | null
          produto_id: string | null
          quantidade: number | null
          rastreio_notificado: boolean
          recebido_por: string | null
          representante_id: string | null
          status_pagamento: string | null
          status_pedido: string | null
          tipo_origem: string | null
          uf_cliente: string | null
          uf_postagem: string | null
          valor: number | null
          valor_original: number | null
        }
        Insert: {
          altura_caixa?: number | null
          box_size?: string | null
          canal?: string | null
          codigo_rastreio?: string | null
          complemento?: string | null
          comprimento_caixa?: number | null
          contato_id?: string | null
          created_at?: string
          criado_por?: string | null
          data?: string
          data_pago?: string | null
          desconto_total?: number | null
          endereco_entrega?: string | null
          entrega_em_maos?: boolean | null
          estoque_debitado?: boolean | null
          estoque_processado?: boolean | null
          etiqueta_codigo?: string | null
          etiqueta_paga?: boolean | null
          etiqueta_url?: string | null
          etiqueta_valor?: number | null
          formato_caixa?: string | null
          gateway_etiqueta?: string | null
          id?: string
          instancia_id?: string | null
          is_free?: boolean | null
          largura_caixa?: number | null
          locked_at?: string | null
          modalidade?: string | null
          obs?: string | null
          observacao?: string | null
          order_number?: number
          peso_envio?: number | null
          preco_unitario?: number | null
          produto?: string | null
          produto_id?: string | null
          quantidade?: number | null
          rastreio_notificado?: boolean
          recebido_por?: string | null
          representante_id?: string | null
          status_pagamento?: string | null
          status_pedido?: string | null
          tipo_origem?: string | null
          uf_cliente?: string | null
          uf_postagem?: string | null
          valor?: number | null
          valor_original?: number | null
        }
        Update: {
          altura_caixa?: number | null
          box_size?: string | null
          canal?: string | null
          codigo_rastreio?: string | null
          complemento?: string | null
          comprimento_caixa?: number | null
          contato_id?: string | null
          created_at?: string
          criado_por?: string | null
          data?: string
          data_pago?: string | null
          desconto_total?: number | null
          endereco_entrega?: string | null
          entrega_em_maos?: boolean | null
          estoque_debitado?: boolean | null
          estoque_processado?: boolean | null
          etiqueta_codigo?: string | null
          etiqueta_paga?: boolean | null
          etiqueta_url?: string | null
          etiqueta_valor?: number | null
          formato_caixa?: string | null
          gateway_etiqueta?: string | null
          id?: string
          instancia_id?: string | null
          is_free?: boolean | null
          largura_caixa?: number | null
          locked_at?: string | null
          modalidade?: string | null
          obs?: string | null
          observacao?: string | null
          order_number?: number
          peso_envio?: number | null
          preco_unitario?: number | null
          produto?: string | null
          produto_id?: string | null
          quantidade?: number | null
          rastreio_notificado?: boolean
          recebido_por?: string | null
          representante_id?: string | null
          status_pagamento?: string | null
          status_pedido?: string | null
          tipo_origem?: string | null
          uf_cliente?: string | null
          uf_postagem?: string | null
          valor?: number | null
          valor_original?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "pedidos_contato_id_fkey"
            columns: ["contato_id"]
            isOneToOne: false
            referencedRelation: "contatos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pedidos_instancia_id_fkey"
            columns: ["instancia_id"]
            isOneToOne: false
            referencedRelation: "instancias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pedidos_produto_id_fkey"
            columns: ["produto_id"]
            isOneToOne: false
            referencedRelation: "produtos"
            referencedColumns: ["id"]
          },
        ]
      }
      perfis_usuario: {
        Row: {
          acesso_kanban: string
          created_at: string
          criado_por: string | null
          email: string | null
          id: string
          instancia_id: string | null
          nome: string
          pode_excluir_card: boolean | null
          servico_tipo: string | null
          socio_key: string | null
          tipo_usuario: string | null
          uf_fixa: string | null
          user_id: string
          ver_menu: Json
        }
        Insert: {
          acesso_kanban?: string
          created_at?: string
          criado_por?: string | null
          email?: string | null
          id?: string
          instancia_id?: string | null
          nome: string
          pode_excluir_card?: boolean | null
          servico_tipo?: string | null
          socio_key?: string | null
          tipo_usuario?: string | null
          uf_fixa?: string | null
          user_id: string
          ver_menu?: Json
        }
        Update: {
          acesso_kanban?: string
          created_at?: string
          criado_por?: string | null
          email?: string | null
          id?: string
          instancia_id?: string | null
          nome?: string
          pode_excluir_card?: boolean | null
          servico_tipo?: string | null
          socio_key?: string | null
          tipo_usuario?: string | null
          uf_fixa?: string | null
          user_id?: string
          ver_menu?: Json
        }
        Relationships: [
          {
            foreignKeyName: "perfis_usuario_instancia_id_fkey"
            columns: ["instancia_id"]
            isOneToOne: false
            referencedRelation: "instancias"
            referencedColumns: ["id"]
          },
        ]
      }
      produtos: {
        Row: {
          ativo: boolean
          box_qty_max: number | null
          box_size: string | null
          cor_card: string | null
          cor_texto: string | null
          created_at: string
          estoque_atual: number
          grupo_id: string | null
          id: string
          limite_estoque: number | null
          nome_oficial: string
          peso: number | null
          posologia: string | null
          preco: number | null
          tag: string
          updated_at: string | null
        }
        Insert: {
          ativo?: boolean
          box_qty_max?: number | null
          box_size?: string | null
          cor_card?: string | null
          cor_texto?: string | null
          created_at?: string
          estoque_atual?: number
          grupo_id?: string | null
          id?: string
          limite_estoque?: number | null
          nome_oficial: string
          peso?: number | null
          posologia?: string | null
          preco?: number | null
          tag: string
          updated_at?: string | null
        }
        Update: {
          ativo?: boolean
          box_qty_max?: number | null
          box_size?: string | null
          cor_card?: string | null
          cor_texto?: string | null
          created_at?: string
          estoque_atual?: number
          grupo_id?: string | null
          id?: string
          limite_estoque?: number | null
          nome_oficial?: string
          peso?: number | null
          posologia?: string | null
          preco?: number | null
          tag?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "produtos_grupo_id_fkey"
            columns: ["grupo_id"]
            isOneToOne: false
            referencedRelation: "produtos_grupos"
            referencedColumns: ["id"]
          },
        ]
      }
      produtos_grupos: {
        Row: {
          cor_grupo: string | null
          created_at: string
          id: string
          nome: string
          ordem: number | null
        }
        Insert: {
          cor_grupo?: string | null
          created_at?: string
          id?: string
          nome: string
          ordem?: number | null
        }
        Update: {
          cor_grupo?: string | null
          created_at?: string
          id?: string
          nome?: string
          ordem?: number | null
        }
        Relationships: []
      }
      remetentes_uf: {
        Row: {
          bairro: string | null
          cep_origem: string | null
          cidade: string | null
          complemento: string | null
          contato_remetente: string | null
          cpf: string | null
          descricao_produto: string | null
          endereco: string | null
          id: string
          nome_remetente: string | null
          numero: string | null
          uf: string
          updated_at: string | null
          valor_unitario: number | null
        }
        Insert: {
          bairro?: string | null
          cep_origem?: string | null
          cidade?: string | null
          complemento?: string | null
          contato_remetente?: string | null
          cpf?: string | null
          descricao_produto?: string | null
          endereco?: string | null
          id?: string
          nome_remetente?: string | null
          numero?: string | null
          uf: string
          updated_at?: string | null
          valor_unitario?: number | null
        }
        Update: {
          bairro?: string | null
          cep_origem?: string | null
          cidade?: string | null
          complemento?: string | null
          contato_remetente?: string | null
          cpf?: string | null
          descricao_produto?: string | null
          endereco?: string | null
          id?: string
          nome_remetente?: string | null
          numero?: string | null
          uf?: string
          updated_at?: string | null
          valor_unitario?: number | null
        }
        Relationships: []
      }
      uf_regioes: {
        Row: {
          codigo: string | null
          id: string
          tag: string | null
          uf: string | null
        }
        Insert: {
          codigo?: string | null
          id?: string
          tag?: string | null
          uf?: string | null
        }
        Update: {
          codigo?: string | null
          id?: string
          tag?: string | null
          uf?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      archive_stale_kanban_cards: { Args: never; Returns: undefined }
      atualizar_estoque_snapshot: { Args: never; Returns: undefined }
      buscar_estoque_completo: { Args: never; Returns: Json }
      calcular_estoque: {
        Args: never
        Returns: {
          entrada: number
          estado: string
          prod_id: string
          prod_nome: string
          saida: number
          saldo: number
        }[]
      }
      create_contato: {
        Args: {
          p_bairro?: string
          p_canal_origem: string
          p_cep?: string
          p_cidade?: string
          p_cidade_uf?: string
          p_complemento?: string
          p_cpf?: string
          p_endereco?: string
          p_nome: string
          p_representante_id?: string
          p_telefone?: string
          p_uf?: string
        }
        Returns: string
      }
      create_produto:
        | {
            Args: {
              p_cor_card?: string
              p_cor_texto?: string
              p_grupo_id?: string
              p_limite_estoque?: number
              p_nome_oficial: string
              p_tag: string
            }
            Returns: string
          }
        | {
            Args: {
              p_box_size?: string
              p_cor_card?: string
              p_cor_texto?: string
              p_grupo_id?: string
              p_limite_estoque?: number
              p_nome_oficial: string
              p_tag: string
            }
            Returns: string
          }
        | {
            Args: {
              p_box_qty_max?: number
              p_box_size?: string
              p_cor_card?: string
              p_cor_texto?: string
              p_grupo_id?: string
              p_limite_estoque?: number
              p_nome_oficial: string
              p_tag: string
            }
            Returns: string
          }
        | {
            Args: {
              p_box_qty_max: number
              p_box_size: string
              p_cor_card: string
              p_cor_texto: string
              p_grupo_id: string
              p_limite_estoque: number
              p_nome_oficial: string
              p_peso?: number
              p_tag: string
            }
            Returns: string
          }
      create_produto_grupo:
        | { Args: { p_nome: string }; Returns: string }
        | { Args: { p_cor?: string; p_nome: string }; Returns: string }
      criar_estoque_snapshot: { Args: never; Returns: undefined }
      criar_lote_estoque: {
        Args: { p_produto_id: string; p_quantidade: number; p_uf: string }
        Returns: Json
      }
      criar_movimentacoes_saida: { Args: never; Returns: undefined }
      criar_pedido:
        | {
            Args: {
              p_canal?: string
              p_contato_id?: string
              p_criado_por?: string
              p_modalidade?: string
              p_produtos?: Json
              p_representante_id?: string
              p_status_pagamento?: string
              p_uf_postagem?: string
              p_valor?: number
            }
            Returns: Json
          }
        | {
            Args: {
              p_canal: string
              p_contato_id: string
              p_criado_por: string
              p_modalidade: string
              p_obs?: string
              p_produtos: Json
              p_status_pagamento: string
              p_uf_postagem: string
              p_valor: number
            }
            Returns: Json
          }
      criar_pedido_v2: {
        Args: {
          p_canal?: string
          p_contato_id: string
          p_criado_por?: string
          p_modalidade?: string
          p_obs?: string
          p_produtos?: Json
          p_status_pagamento?: string
          p_uf_postagem?: string
          p_valor?: number
        }
        Returns: Json
      }
      criar_usuario:
        | {
            Args: {
              p_apelido: string
              p_criado_por?: string
              p_email: string
              p_instancia_nome?: string
              p_instancia_uf?: string
              p_send_invite?: boolean
              p_senha?: string
              p_servico_tipo?: string
              p_tipo: string
              p_uf?: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_apelido: string
              p_criado_por?: string
              p_email: string
              p_instancia_id?: string
              p_senha: string
              p_servico_tipo?: string
              p_tipo: string
              p_uf?: string
            }
            Returns: Json
          }
      deletar_usuario: {
        Args: { p_admin_password: string; p_user_id: string }
        Returns: Json
      }
      deletar_venda_completa: {
        Args: { p_lancamento_id: string }
        Returns: Json
      }
      delete_produto: { Args: { p_id: string }; Returns: undefined }
      delete_produto_grupo: { Args: { p_id: string }; Returns: undefined }
      gerar_movimentacoes_saida: { Args: never; Returns: undefined }
      get_estoque_completo: {
        Args: never
        Returns: {
          entrada: number
          estado: string
          prod_id: string
          prod_nome: string
          saida: number
          saldo: number
        }[]
      }
      get_estoque_produto: {
        Args: { p_produto_id?: string; p_uf?: string }
        Returns: {
          entradas: number
          produto_id: string
          produto_nome: string
          saidas_pedidos: number
          saldo: number
          uf: string
        }[]
      }
      limpar_movimentacoes_antigas: {
        Args: { p_dias?: string }
        Returns: {
          registros_apagados: number
          saldo_restaurado: Json
        }[]
      }
      listar_socios: {
        Args: never
        Returns: {
          nome: string
          socio_key: string
        }[]
      }
      perform_midnight_lead_migration: { Args: never; Returns: Json }
      process_venda:
        | {
            Args: {
              p_canal: string
              p_contato_id: string
              p_criado_por?: string
              p_modalidade?: string
              p_obs?: string
              p_produtos?: Json
              p_socio?: string
              p_uf_postagem?: string
              p_valor: number
            }
            Returns: Json
          }
        | {
            Args: {
              p_canal: string
              p_contato_id: string
              p_criado_por?: string
              p_modalidade?: string
              p_produtos: Json
              p_socio: string
              p_status_pagamento?: string
              p_uf_postagem?: string
              p_valor: number
            }
            Returns: undefined
          }
      processar_pedido_estoque_trigger: {
        Args: { p_pedido_id: string; p_uf_postagem?: string }
        Returns: Json
      }
      processar_todos_estoque_pendente: { Args: never; Returns: Json }
      reprocessar_pedidos_estoque: { Args: never; Returns: Json }
      salvar_remetente: {
        Args: {
          p_bairro: string
          p_cep_origem: string
          p_cidade: string
          p_complemento: string
          p_contato_remetente: string
          p_cpf: string
          p_descricao_produto: string
          p_endereco: string
          p_nome_remetente: string
          p_numero: string
          p_uf_in: string
          p_valor_unitario: number
        }
        Returns: undefined
      }
      sincronizar_movimentacoes_pedidos: { Args: never; Returns: Json }
      update_produto:
        | {
            Args: {
              p_cor_card: string
              p_cor_texto: string
              p_grupo_id?: string
              p_id: string
              p_limite_estoque: number
              p_nome_oficial: string
              p_tag: string
            }
            Returns: undefined
          }
        | {
            Args: {
              p_box_size?: string
              p_cor_card: string
              p_cor_texto: string
              p_grupo_id: string
              p_id: string
              p_limite_estoque: number
              p_nome_oficial: string
              p_tag: string
            }
            Returns: undefined
          }
        | {
            Args: {
              p_box_qty_max?: number
              p_box_size?: string
              p_cor_card: string
              p_cor_texto: string
              p_grupo_id: string
              p_id: string
              p_limite_estoque: number
              p_nome_oficial: string
              p_tag: string
            }
            Returns: undefined
          }
        | {
            Args: {
              p_box_qty_max: number
              p_box_size: string
              p_cor_card: string
              p_cor_texto: string
              p_grupo_id: string
              p_id: string
              p_limite_estoque: number
              p_nome_oficial: string
              p_peso?: number
              p_tag: string
            }
            Returns: undefined
          }
      update_produto_estoque: {
        Args: { p_produto_id: string }
        Returns: undefined
      }
      update_produto_grupo: {
        Args: { p_cor: string; p_id: string; p_nome: string }
        Returns: undefined
      }
      update_produto_status: {
        Args: { p_ativo: boolean; p_id: string }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
